package com.example.mht_viewer_app

import android.net.Uri
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
            val mhtUris = children
                .filter { f ->
                    val name = f.name?.lowercase() ?: ""
                    name.endsWith(".mht") || name.endsWith(".mhtml")
                }
                .map { it.uri.toString() }
                .toList()

            result.success(mhtUris)
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
}
