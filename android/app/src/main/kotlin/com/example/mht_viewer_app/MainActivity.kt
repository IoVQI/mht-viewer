package com.example.mht_viewer_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "mht_viewer_app/file"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listMhtFiles" -> {
                        val dirUri = call.argument<String>("uri") ?: ""
                        listMhtFiles(Uri.parse(dirUri), result)
                    }
                    "readFile" -> {
                        val fileUri = call.argument<String>("uri") ?: ""
                        readFileToCache(Uri.parse(fileUri), result)
                    }
                    "isManageStorageGranted" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                            Environment.isExternalStorageManager()
                        else true
                    )
                    "convertToUtf8" -> {
                        val fileUri = call.argument<String>("uri") ?: ""
                        val charset = call.argument<String>("charset") ?: "GBK"
                        convertToUtf8(Uri.parse(fileUri), charset, result)
                    }
                    "requestManageStorage" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:${packageName}")
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listMhtFiles(treeUri: Uri, result: MethodChannel.Result) {
        try {
            val rootDir = DocumentFile.fromTreeUri(this, treeUri)
            if (rootDir == null || !rootDir.isDirectory) {
                result.success(emptyList<String>())
                return
            }

            val children = rootDir.listFiles()
            val mhtFiles = children
                .filter { f ->
                    val name = f.name?.lowercase() ?: ""
                    name.endsWith(".mht") || name.endsWith(".mhtml")
                }
                .map { mapOf("uri" to it.uri.toString(), "name" to (it.name ?: "")) }
                .toList()

            result.success(mhtFiles)
        } catch (e: Exception) {
            result.success(emptyList<String>())
        }
    }

    private fun readFileToCache(fileUri: Uri, result: MethodChannel.Result) {
        try {
            val tempFile = File(cacheDir, "mht_${System.currentTimeMillis()}.mht")
            contentResolver.openInputStream(fileUri)?.use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: run {
                result.error("READ_ERROR", "Cannot open input stream", null)
                return
            }
            result.success(tempFile.absolutePath)
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message, null)
        }
    }

    private fun convertToUtf8(fileUri: Uri, charset: String, result: MethodChannel.Result) {
        try {
            val bytes = contentResolver.openInputStream(fileUri)?.use { it.readBytes() }
                ?: run {
                    result.error("READ_ERROR", "Cannot open input stream", null)
                    return
                }
            val text = String(bytes, charset(charset))
            val tempFile = File(cacheDir, "mht_utf8_${System.currentTimeMillis()}.mht")
            tempFile.writeBytes(text.toByteArray(Charsets.UTF_8))
            result.success(tempFile.absolutePath)
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message, null)
        }
    }
}
