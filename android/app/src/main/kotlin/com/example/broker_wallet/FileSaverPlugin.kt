package com.example.broker_wallet

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.File
import java.io.FileOutputStream

class FileSaverPlugin : MethodCallHandler {
    companion object {
        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "file_saver")
            channel.setMethodCallHandler(FileSaverPlugin().apply { 
                this.context = context 
            })
        }
    }

    private lateinit var context: Context

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveFileToDownloads" -> {
                try {
                    val fileName = call.argument<String>("fileName")
                    val fileBytes = call.argument<ByteArray>("fileBytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

                    if (fileName == null || fileBytes == null) {
                        result.error("INVALID_ARGS", "fileName and fileBytes are required", null)
                        return
                    }

                    val savedUri = saveFileToDownloads(fileName, fileBytes, mimeType)
                    if (savedUri != null) {
                        result.success(mapOf(
                            "success" to true,
                            "uri" to savedUri.toString(),
                            "path" to getFilePathFromUri(savedUri.toString())
                        ))
                    } else {
                        result.error("SAVE_FAILED", "Failed to save file", null)
                    }
                } catch (e: Exception) {
                    result.error("EXCEPTION", e.message, null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun saveFileToDownloads(fileName: String, fileBytes: ByteArray, mimeType: String): android.net.Uri? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ (API 29+) - Use MediaStore
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }

                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)

                uri?.let { insertUri ->
                    resolver.openOutputStream(insertUri)?.use { outputStream ->
                        outputStream.write(fileBytes)
                        outputStream.flush()
                    }
                    insertUri
                }
            } else {
                // Android 9 and below - Use traditional method
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val file = File(downloadsDir, fileName)
                
                FileOutputStream(file).use { outputStream ->
                    outputStream.write(fileBytes)
                    outputStream.flush()
                }
                
                android.net.Uri.fromFile(file)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getFilePathFromUri(uriString: String): String? {
        return try {
            // For MediaStore URIs, we can't get a direct file path
            // But we can provide a user-friendly location description
            if (uriString.contains("content://")) {
                "Downloads folder (accessible via Files app)"
            } else {
                uriString.replace("file://", "")
            }
        } catch (e: Exception) {
            null
        }
    }
}
