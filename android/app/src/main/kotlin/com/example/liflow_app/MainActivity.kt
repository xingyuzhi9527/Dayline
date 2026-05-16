package com.example.liflow_app

import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingDirectoryResult: MethodChannel.Result? = null
    private val PICK_DIRECTORY = 1001

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
        callback.success(uri.toString())
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
                    "hasTreeAccess" -> hasTreeAccess(call, result)
                    "writeTextFile" -> writeTextFile(call, result)
                    "readTextFile" -> readTextFile(call, result)
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("markdown_storage_error", error.message, null)
            }
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

    private fun writeTextFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
            ?: throw IllegalArgumentException("Missing: treeUri")
        val relativePath = call.argument<String>("relativePath")
            ?: throw IllegalArgumentException("Missing: relativePath")
        val content = call.argument<String>("content")
            ?: throw IllegalArgumentException("Missing: content")

        val file = resolveFile(Uri.parse(treeUri), relativePath, true)
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
            return current?.createFile("text/markdown", fileName)
                ?: throw IllegalStateException("Cannot create file: $fileName")
        }
        throw IllegalStateException("Cannot resolve file: $fileName")
    }
}
