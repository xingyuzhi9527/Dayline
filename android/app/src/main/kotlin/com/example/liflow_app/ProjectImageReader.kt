package com.example.liflow_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import androidx.documentfile.provider.DocumentFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest

/** Original images stay in the document tree. Only bounded previews reach disk. */
internal class ProjectImageReader(private val context: Context) {
    fun read(file: DocumentFile, thumbnail: Boolean): ByteArray {
        val resolver = context.contentResolver
        if (!thumbnail) {
            return requireNotNull(resolver.openInputStream(file.uri)).use { it.readBytes() }
        }
        val key = "${file.uri}:${file.lastModified()}:${file.length()}"
        val name = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val directory = File(context.cacheDir, "project-image-thumbnails").apply { mkdirs() }
        val cached = File(directory, "$name.png")
        if (cached.exists()) {
            cached.setLastModified(System.currentTimeMillis())
            return cached.readBytes()
        }

        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        requireNotNull(resolver.openInputStream(file.uri)).use {
            BitmapFactory.decodeStream(it, null, options)
        }
        check(options.outWidth > 0 && options.outHeight > 0) { "Unsupported image" }
        options.inJustDecodeBounds = false
        options.inSampleSize = 1
        while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 640) {
            options.inSampleSize *= 2
        }
        val bitmap = requireNotNull(resolver.openInputStream(file.uri)).use {
            BitmapFactory.decodeStream(it, null, options)
        } ?: throw IllegalStateException("Cannot decode image")
        val orientation = try {
            requireNotNull(resolver.openInputStream(file.uri)).use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
            }
        } catch (_: Exception) { 1 }
        val matrix = Matrix().apply {
            when (orientation) {
                2 -> setScale(-1f, 1f)
                3 -> setRotate(180f)
                4 -> { setRotate(180f); postScale(-1f, 1f) }
                5 -> { setRotate(90f); postScale(-1f, 1f) }
                6 -> setRotate(90f)
                7 -> { setRotate(-90f); postScale(-1f, 1f) }
                8 -> setRotate(-90f)
            }
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        val preview = Bitmap.createScaledBitmap(
            rotated,
            (rotated.width * minOf(1.0, 320.0 / maxOf(rotated.width, rotated.height))).toInt().coerceAtLeast(1),
            (rotated.height * minOf(1.0, 320.0 / maxOf(rotated.width, rotated.height))).toInt().coerceAtLeast(1),
            true,
        )
        val bytes = try {
            ByteArrayOutputStream().use {
                check(preview.compress(Bitmap.CompressFormat.PNG, 100, it)) { "Cannot encode preview" }
                it.toByteArray()
            }
        } finally {
            if (preview !== rotated && preview !== bitmap) preview.recycle()
            if (rotated !== bitmap) rotated.recycle()
            bitmap.recycle()
        }
        // Cache failures must not prevent reading the original image.
        try {
            cached.writeBytes(bytes)
            val files = directory.listFiles()?.sortedBy { it.lastModified() }.orEmpty()
            var total = files.sumOf { it.length() }
            for (entry in files) {
                if (total <= 32L * 1024 * 1024) break
                val size = entry.length()
                if (entry.delete()) total -= size
            }
        } catch (_: Exception) { cached.delete() }
        return bytes
    }
}
