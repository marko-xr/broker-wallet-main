package com.example.broker_wallet

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.Executors

/**
 * The "file_saver" channel.
 *
 * - saveFileToDownloads: the original method used by Combine PDFs, Images to PDF
 *   and Signature. Same arguments and same reply; it now also refuses a null
 *   output stream, keeps the entry pending until it is complete, and removes the
 *   entry if writing fails, so no empty or half-written file is left in
 *   Downloads.
 * - exportFileToDownloads: used by the Scanner. Streams a file from the app's
 *   private storage into Downloads, so a document is never passed through the
 *   channel as one byte array.
 * - copyContentUriToFile: used by the Scanner to read a content:// URI through
 *   the content resolver into an app-owned file.
 *
 * Android 10+ uses MediaStore Downloads (no storage permission needed); Android
 * 9 and below write to the public Downloads folder (the legacy storage
 * permission, requested by Dart, is needed there). Nothing here asks for All
 * Files Access.
 */
class FileSaverPlugin : MethodCallHandler {
    companion object {
        private const val COPY_BUFFER_BYTES = 64 * 1024

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "file_saver")
            channel.setMethodCallHandler(FileSaverPlugin().apply {
                this.context = context
            })
        }
    }

    private lateinit var context: Context
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private class SavedFile(val uri: Uri, val displayName: String)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveFileToDownloads" -> saveBytes(call, result)
            "exportFileToDownloads" -> exportFile(call, result)
            "copyContentUriToFile" -> copyContentUri(call, result)
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- bytes

    private fun saveBytes(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val fileBytes = call.argument<ByteArray>("fileBytes")
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
        if (fileName == null || fileBytes == null) {
            result.error("INVALID_ARGS", "fileName and fileBytes are required", null)
            return
        }
        runAsync(result) {
            val saved = saveToDownloads(fileName, mimeType) { out -> out.write(fileBytes) }
            mapOf(
                "success" to true,
                "uri" to saved.uri.toString(),
                "path" to "Downloads folder (accessible via Files app)"
            )
        }
    }

    // ----------------------------------------------------------- file export

    private fun exportFile(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType")
        if (sourcePath == null || fileName == null || mimeType == null) {
            result.error("INVALID_ARGS", "sourcePath, fileName and mimeType are required", null)
            return
        }
        runAsync(result) {
            val source = privateFile(sourcePath)
            if (source == null || !source.isFile || source.length() == 0L) {
                throw SourceInvalid()
            }
            val saved = FileInputStream(source).use { input ->
                saveToDownloads(fileName, mimeType) { out -> input.copyTo(out, COPY_BUFFER_BYTES) }
            }
            mapOf(
                "success" to true,
                "uri" to saved.uri.toString(),
                "displayName" to saved.displayName
            )
        }
    }

    private class SourceInvalid : Exception()

    // ------------------------------------------------------------ content uri

    private fun copyContentUri(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        val destinationPath = call.argument<String>("destinationPath")
        if (uriText == null || destinationPath == null) {
            result.error("INVALID_ARGS", "uri and destinationPath are required", null)
            return
        }
        runAsync(result) {
            val uri = Uri.parse(uriText)
            if (uri.scheme != "content") throw SourceInvalid()
            val destination = privateFile(destinationPath, allowMissing = true) ?: throw SourceInvalid()
            destination.parentFile?.mkdirs()
            val part = File(destination.path + ".part")
            var copied = 0L
            try {
                val input = context.contentResolver.openInputStream(uri) ?: throw SourceInvalid()
                input.use { stream ->
                    FileOutputStream(part).use { out ->
                        copied = stream.copyTo(out, COPY_BUFFER_BYTES)
                        out.flush()
                    }
                }
                if (copied <= 0L) throw IOException("empty content")
                if (!part.renameTo(destination)) throw IOException("rename failed")
            } catch (e: Exception) {
                part.delete()
                destination.delete()
                throw e
            }
            mapOf("success" to true, "bytes" to copied)
        }
    }

    // ------------------------------------------------------------- Downloads

    private fun saveToDownloads(
        fileName: String,
        mimeType: String,
        write: (OutputStream) -> Unit
    ): SavedFile {
        val name = safeDisplayName(fileName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(name, mimeType, write)
        } else {
            saveToPublicFolder(name, write)
        }
    }

    private fun saveWithMediaStore(
        name: String,
        mimeType: String,
        write: (OutputStream) -> Unit
    ): SavedFile {
        val resolver = context.contentResolver
        val pending = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        // MediaStore picks a free name ("name (1).pdf") instead of replacing a
        // file that is already in Downloads.
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, pending)
            ?: throw IOException("MediaStore insert failed")
        try {
            val out = resolver.openOutputStream(uri, "w")
                ?: throw IOException("No output stream for the new Downloads entry")
            out.use {
                write(it)
                it.flush()
            }
            val complete = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, complete, null, null)
            return SavedFile(uri, queryDisplayName(uri) ?: name)
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw e
        }
    }

    private fun saveToPublicFolder(name: String, write: (OutputStream) -> Unit): SavedFile {
        val folder = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!folder.exists() && !folder.mkdirs()) throw IOException("Downloads folder unavailable")
        val target = uniqueFile(folder, name)
        val part = File(folder, "." + target.name + ".part")
        try {
            FileOutputStream(part).use {
                write(it)
                it.flush()
            }
            if (!part.renameTo(target)) throw IOException("Could not finish the file")
            return SavedFile(Uri.fromFile(target), target.name)
        } catch (e: Exception) {
            part.delete()
            throw e
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (_: Exception) {
            null
        }
    }

    private fun uniqueFile(folder: File, name: String): File {
        var candidate = File(folder, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var counter = 1
        while (true) {
            candidate = File(folder, "$base ($counter)$extension")
            if (!candidate.exists()) return candidate
            counter++
        }
    }

    /** A file name with path separators and characters Android refuses removed. */
    private fun safeDisplayName(raw: String): String {
        var name = raw.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_").trim()
        name = name.trimStart('.')
        if (name.length > 120) {
            val dot = name.lastIndexOf('.')
            val extension = if (dot > 0 && name.length - dot <= 8) name.substring(dot) else ""
            name = name.substring(0, 120 - extension.length) + extension
        }
        return if (name.isEmpty()) "document" else name
    }

    /**
     * [path] as a canonical file, only when it lies inside this app's own data
     * folder; null otherwise. A path elsewhere (another app's folder, shared
     * storage) is never opened.
     */
    private fun privateFile(path: String, allowMissing: Boolean = false): File? {
        return try {
            val file = File(path).canonicalFile
            val root = context.filesDir.parentFile?.canonicalFile ?: return null
            val inside = file.path.startsWith(root.path + File.separator)
            if (!inside) return null
            if (!allowMissing && !file.exists()) return null
            file
        } catch (_: IOException) {
            null
        }
    }

    // ----------------------------------------------------------------- async

    private fun runAsync(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: SourceInvalid) {
                mainHandler.post { result.error("SOURCE_INVALID", "The file cannot be read", null) }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("PERMISSION_DENIED", "Not allowed to write the file", null) }
            } catch (e: Exception) {
                val full = e.message?.let {
                    it.contains("ENOSPC") || it.contains("No space left", ignoreCase = true)
                } ?: false
                mainHandler.post {
                    if (full) {
                        result.error("STORAGE_FULL", "The phone is out of storage space", null)
                    } else {
                        result.error("EXPORT_FAILED", "The file could not be saved", null)
                    }
                }
            }
        }
    }
}
