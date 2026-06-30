package com.example.liflow_app

import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingDirectoryResult: MethodChannel.Result? = null
    private var pendingDocumentImportResult: MethodChannel.Result? = null
    private var pendingDocumentTreeUri: String? = null
    private var pendingDocumentTargetPath: String? = null
    private var pendingDocumentMarkdownPath: String? = null
    private var audioChannel: MethodChannel? = null
    private var mediaPlayer: MediaPlayer? = null
    private var playingAudioPath: String? = null
    private val PICK_DIRECTORY = 1001
    private val PICK_DOCUMENT = 1002

    override fun onDestroy() {
        releaseAudioPlayer(notifyStop = false)
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_DOCUMENT) {
            handlePickedDocument(resultCode, data)
            return
        }
        if (requestCode != PICK_DIRECTORY) return

        val callback = pendingDirectoryResult
        pendingDirectoryResult = null
        if (callback == null) return

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            callback.success(null)
            return
        }

        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        callback.success(describeTree(uri))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "liflow/markdown_storage",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "pickDirectory" -> pickDirectory(result)
                    "describeTree" -> describeTree(call, result)
                    "hasTreeAccess" -> hasTreeAccess(call, result)
                    "ensureDirectories" -> ensureDirectories(call, result)
                    "listFiles" -> listFiles(call, result)
                    "importDocument" -> importDocument(call, result)
                    "openDocument" -> openDocument(call, result)
                    "deleteDocument" -> deleteDocument(call, result)
                    "writeBinaryFile" -> writeBinaryFile(call, result)
                    "writeTextFile" -> writeTextFile(call, result)
                    "readTextFile" -> readTextFile(call, result)
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("markdown_storage_error", error.message, null)
            }
        }

        audioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "liflow/audio_player",
        )
        audioChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "play" -> playAudio(call, result)
                    "stop" -> {
                        releaseAudioPlayer(notifyStop = true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                releaseAudioPlayer(notifyStop = true)
                result.error("audio_player_error", error.message, null)
            }
        }
    }

    private fun playAudio(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
            ?: throw IllegalArgumentException("Missing: path")
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("Audio file not found: $path")
        }

        releaseAudioPlayer(notifyStop = false)
        playingAudioPath = path
        mediaPlayer = MediaPlayer().apply {
            setDataSource(path)
            setOnCompletionListener {
                val completedPath = playingAudioPath
                releaseAudioPlayer(notifyStop = false)
                audioChannel?.invokeMethod(
                    "onPlaybackComplete",
                    mapOf("path" to completedPath),
                )
            }
            setOnErrorListener { _, _, _ ->
                val failedPath = playingAudioPath
                releaseAudioPlayer(notifyStop = false)
                audioChannel?.invokeMethod(
                    "onPlaybackStop",
                    mapOf("path" to failedPath),
                )
                true
            }
            prepare()
            start()
        }
        result.success(null)
    }

    private fun releaseAudioPlayer(notifyStop: Boolean) {
        val stoppedPath = playingAudioPath
        mediaPlayer?.setOnCompletionListener(null)
        mediaPlayer?.setOnErrorListener(null)
        try {
            if (mediaPlayer?.isPlaying == true) {
                mediaPlayer?.stop()
            }
        } catch (_: Throwable) {
        }
        mediaPlayer?.release()
        mediaPlayer = null
        playingAudioPath = null

        if (notifyStop && stoppedPath != null) {
            audioChannel?.invokeMethod("onPlaybackStop", mapOf("path" to stoppedPath))
        }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingDirectoryResult != null) {
            result.error("picker_busy", "Directory picker is already active.", null)
            return
        }
        pendingDirectoryResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, PICK_DIRECTORY)
    }

    private fun hasTreeAccess(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val hasAccess = contentResolver.persistedUriPermissions.any {
            it.uri.toString() == treeUri && it.isReadPermission && it.isWritePermission
        }
        result.success(hasAccess)
    }

    private fun describeTree(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        result.success(describeTree(Uri.parse(treeUri)))
    }

    private fun describeTree(uri: Uri): Map<String, Any?> {
        val root = DocumentFile.fromTreeUri(this, uri)
        return mapOf(
            "treeUri" to uri.toString(),
            "name" to root?.name,
        )
    }

    private fun ensureDirectories(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val paths = call.argument<List<String>>("paths") ?: emptyList()
        for (path in paths) {
            resolveDirectory(Uri.parse(treeUri), path, true)
        }
        result.success(null)
    }

    private fun listFiles(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val roots = call.argument<List<String>>("roots") ?: emptyList()

        Thread {
            try {
                val rows = mutableListOf<Map<String, Any?>>()

                for (rootPath in roots) {
                    val root = try {
                        resolveDirectory(Uri.parse(treeUri), rootPath, false)
                    } catch (_: Throwable) {
                        null
                    }
                    if (root != null) {
                        collectFiles(root, rootPath.trim('/'), rows)
                    }
                }

                runOnUiThread { result.success(rows) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("list_files_error", error.message, null)
                }
            }
        }.start()
    }

    private fun importDocument(call: MethodCall, result: MethodChannel.Result) {
        if (pendingDocumentImportResult != null) {
            result.error("picker_busy", "Document picker is already active.", null)
            return
        }
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val documentsPath = call.argument<String>("documentsPath")
            ?.takeIf { it.isNotBlank() }
            ?: "documents"
        val markdownPath = call.argument<String>("markdownPath")
            ?.takeIf { it.isNotBlank() }
        pendingDocumentImportResult = result
        pendingDocumentTreeUri = treeUri
        pendingDocumentTargetPath = documentsPath
        pendingDocumentMarkdownPath = markdownPath

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, PICK_DOCUMENT)
    }

    private fun handlePickedDocument(resultCode: Int, data: Intent?) {
        val callback = pendingDocumentImportResult
        val treeUri = pendingDocumentTreeUri
        val documentsPath = pendingDocumentTargetPath ?: "documents"
        val markdownPath = pendingDocumentMarkdownPath
        pendingDocumentImportResult = null
        pendingDocumentTreeUri = null
        pendingDocumentTargetPath = null
        pendingDocumentMarkdownPath = null
        if (callback == null) return

        val sourceUri = data?.data
        if (resultCode != RESULT_OK || sourceUri == null || treeUri == null) {
            callback.success(null)
            return
        }

        Thread {
            try {
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (flags != 0) {
                    try {
                        contentResolver.takePersistableUriPermission(sourceUri, flags)
                    } catch (_: Throwable) {
                        // Some providers grant temporary read access only. Copying still works.
                    }
                }

                val imported = copyDocumentIntoTree(
                    Uri.parse(treeUri),
                    sourceUri,
                    documentsPath,
                    markdownPath,
                )
                runOnUiThread { callback.success(imported) }
            } catch (error: Throwable) {
                runOnUiThread {
                    callback.error("document_import_error", error.message, null)
                }
            }
        }.start()
    }

    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val relativePath = call.argument<String>("relativePath")
            ?: throw IllegalArgumentException("Missing: relativePath")
        val requestedMime = call.argument<String>("mimeType")

        val file = resolveFile(Uri.parse(treeUri), relativePath, false)
        val mimeType = requestedMime?.takeIf { it.isNotBlank() }
            ?: file.type
            ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(file.uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            startActivity(Intent.createChooser(intent, "打开文档"))
            result.success(null)
        } catch (error: Throwable) {
            result.error("document_open_error", error.message, null)
        }
    }

    private fun deleteDocument(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val relativePath = call.argument<String>("relativePath")
            ?: throw IllegalArgumentException("Missing: relativePath")

        val file = resolveFile(Uri.parse(treeUri), relativePath, false)
        if (!file.delete()) {
            throw IllegalStateException("Cannot delete document: $relativePath")
        }
        result.success(null)
    }

    private fun writeBinaryFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val relativePath = call.argument<String>("relativePath")
            ?: throw IllegalArgumentException("Missing: relativePath")
        val sourcePath = call.argument<String>("sourcePath")
            ?: throw IllegalArgumentException("Missing: sourcePath")
        val mimeType = call.argument<String>("mimeType")
            ?.takeIf { it.isNotBlank() }
            ?: "application/octet-stream"

        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalStateException("Source file not found: $sourcePath")
        }

        val targetFile = resolveFile(Uri.parse(treeUri), relativePath, true, mimeType)
        val output = contentResolver.openOutputStream(targetFile.uri, "w")
            ?: throw IllegalStateException("Cannot open output stream")
        sourceFile.inputStream().use { source ->
            output.use { target ->
                source.copyTo(target)
            }
        }
        result.success(null)
    }

    private fun writeTextFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val relativePath = call.argument<String>("relativePath")
            ?: throw IllegalArgumentException("Missing: relativePath")
        val content = call.argument<String>("content")
            ?: throw IllegalArgumentException("Missing: content")

        val file = resolveFile(Uri.parse(treeUri), relativePath, true, "text/markdown")
        val stream = contentResolver.openOutputStream(file.uri, "wt")
            ?: throw IllegalStateException("Cannot open output stream")
        stream.bufferedWriter(Charsets.UTF_8).use { it.write(content) }
        result.success(null)
    }

    private fun readTextFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val relativePath = call.argument<String>("relativePath")
            ?: throw IllegalArgumentException("Missing: relativePath")

        val file = resolveFile(Uri.parse(treeUri), relativePath, false)
        val stream = contentResolver.openInputStream(file.uri)
            ?: throw IllegalStateException("Cannot open input stream")
        val text = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        result.success(text)
    }

    private fun resolveFile(
        treeUri: Uri,
        relativePath: String,
        createIfMissing: Boolean,
        mimeType: String = "text/markdown",
    ): DocumentFile {
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("Cannot access folder")

        val segments = relativePath
            .split("/")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        require(segments.isNotEmpty()) { "Relative path must not be empty" }

        var current: DocumentFile = root
        for (segment in segments.dropLast(1)) {
            val dir = current.findFile(segment)?.takeIf { it.isDirectory }
            current = if (dir != null) {
                dir
            } else if (createIfMissing) {
                current.createDirectory(segment)
                    ?: throw IllegalStateException("Cannot create dir: $segment")
            } else {
                throw IllegalStateException("Cannot resolve dir: $segment")
            }
        }

        val fileName = segments.last()
        val existing = current?.findFile(fileName)?.takeIf { it.isFile }
        if (existing != null) return existing
        if (createIfMissing) {
            return current?.createFile(mimeType, fileName)
                ?: throw IllegalStateException("Cannot create file: $fileName")
        }
        throw IllegalStateException("Cannot resolve file: $fileName")
    }

    private fun resolveDirectory(
        treeUri: Uri,
        relativePath: String,
        createIfMissing: Boolean,
    ): DocumentFile {
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("Cannot access folder")
        val segments = relativePath
            .split("/")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        var current: DocumentFile = root
        for (segment in segments) {
            val dir = current.findFile(segment)?.takeIf { it.isDirectory }
            current = if (dir != null) {
                dir
            } else if (createIfMissing) {
                current.createDirectory(segment)
                    ?: throw IllegalStateException("Cannot create dir: $segment")
            } else {
                throw IllegalStateException("Cannot resolve dir: $segment")
            }
        }
        return current
    }

    private fun collectFiles(
        dir: DocumentFile,
        relativeDir: String,
        rows: MutableList<Map<String, Any?>>,
    ) {
        for (child in dir.listFiles()) {
            val childRelativePath = if (relativeDir.isBlank()) {
                child.name ?: ""
            } else {
                "$relativeDir/${child.name ?: ""}"
            }
            if (child.isDirectory) {
                collectFiles(child, childRelativePath, rows)
            } else if (child.isFile) {
                rows.add(
                    mapOf(
                        "name" to child.name,
                        "relativePath" to childRelativePath,
                        "mimeType" to child.type,
                        "sizeBytes" to child.length(),
                        "updatedAt" to child.lastModified(),
                    ),
                )
            }
        }
    }

    private fun copyDocumentIntoTree(
        treeUri: Uri,
        sourceUri: Uri,
        documentsPath: String,
        markdownPath: String?,
    ): Map<String, Any?> {
        val sourceName = queryDisplayName(sourceUri) ?: "document"
        val mimeType = contentResolver.getType(sourceUri) ?: "application/octet-stream"
        val targetPath = if (markdownPath != null && isMarkdownDocument(sourceName, mimeType)) {
            markdownPath
        } else {
            documentsPath
        }
        val documentsDir = resolveDirectory(treeUri, targetPath, true)
        val targetName = uniqueFileName(documentsDir, sourceName)
        val targetFile = documentsDir.createFile(mimeType, targetName)
            ?: throw IllegalStateException("Cannot create document: $targetName")

        val input = contentResolver.openInputStream(sourceUri)
            ?: throw IllegalStateException("Cannot open picked document")
        val output = contentResolver.openOutputStream(targetFile.uri, "w")
            ?: throw IllegalStateException("Cannot open imported document")
        input.use { source ->
            output.use { target ->
                source.copyTo(target)
            }
        }

        return mapOf(
            "name" to targetFile.name,
            "relativePath" to "${targetPath.trim('/')}/${targetFile.name}",
            "mimeType" to targetFile.type,
            "sizeBytes" to targetFile.length(),
            "updatedAt" to targetFile.lastModified(),
        )
    }

    private fun isMarkdownDocument(fileName: String, mimeType: String): Boolean {
        val lowerName = fileName.lowercase()
        val lowerMime = mimeType.lowercase()
        return lowerName.endsWith(".md") ||
            lowerName.endsWith(".markdown") ||
            lowerMime == "text/markdown" ||
            lowerMime == "text/x-markdown"
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun uniqueFileName(dir: DocumentFile, desiredName: String): String {
        if (dir.findFile(desiredName) == null) return desiredName
        val dot = desiredName.lastIndexOf('.')
        val base = if (dot > 0) desiredName.substring(0, dot) else desiredName
        val ext = if (dot > 0) desiredName.substring(dot) else ""
        var index = 2
        while (true) {
            val candidate = "$base ($index)$ext"
            if (dir.findFile(candidate) == null) return candidate
            index++
        }
    }
}
