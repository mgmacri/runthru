package com.runthru.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.runthru/android_file_access"
        private const val SHARE_CHANNEL = "com.runthru/share_intent"
        private const val TAG = "RunThruAndroid"
        private const val REQUEST_PICK_DIRECTORY = 9001
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingDestPath: String? = null
    private var shareChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share intent channel — forwards incoming share intents to Dart.
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL
        )

        // Existing file access channel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAndCopyPdfs" -> {
                        val destPath = call.argument<String>("destPath")
                        if (destPath == null) {
                            result.error("INVALID_ARGS", "destPath is required", null)
                            return@setMethodCallHandler
                        }
                        if (pendingResult != null) {
                            result.error("ALREADY_ACTIVE", "A pick operation is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        pendingDestPath = destPath
                        launchDirectoryPicker()
                    }
                    else -> result.notImplemented()
                }
            }

        // Handle cold-start share intent.
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return

        when (intent.action) {
            Intent.ACTION_SEND -> handleActionSend(intent)
            Intent.ACTION_VIEW -> handleActionView(intent)
        }
    }

    private fun handleActionSend(intent: Intent) {
        val mimeType = intent.type ?: return

        when {
            mimeType.startsWith("text/") -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
                val type = if (mimeType == "text/html") "htmlText" else "text"
                shareChannel?.invokeMethod("onSharedContent", mapOf(
                    "type" to type,
                    "data" to text,
                    "mimeType" to mimeType
                ))
            }
            mimeType == "application/pdf" || mimeType == "application/epub+zip" -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
                copySharedFileAndForward(uri, mimeType)
            }
        }
    }

    private fun handleActionView(intent: Intent) {
        val uri = intent.data ?: return
        val url = uri.toString()
        shareChannel?.invokeMethod("onSharedContent", mapOf(
            "type" to "url",
            "data" to url
        ))
    }

    /**
     * Copies a shared file (PDF/EPUB) to app-private storage, then forwards
     * the private path to Dart. This ensures we don't hold URI permissions
     * indefinitely (security best practice).
     */
    private fun copySharedFileAndForward(uri: Uri, mimeType: String) {
        Thread {
            try {
                val inputStream = contentResolver.openInputStream(uri) ?: return@Thread

                val type = if (mimeType == "application/pdf") "pdfFile" else "epubFile"
                val ext = if (mimeType == "application/pdf") "pdf" else "epub"
                val fileName = getFileNameFromUri(uri) ?: "shared_${System.currentTimeMillis()}.$ext"
                val destDir = File(filesDir, "shared_imports")
                if (!destDir.exists()) destDir.mkdirs()
                val destFile = File(destDir, fileName)

                inputStream.use { input ->
                    destFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                Log.d(TAG, "Copied shared file to: ${destFile.absolutePath}")

                runOnUiThread {
                    shareChannel?.invokeMethod("onSharedContent", mapOf(
                        "type" to type,
                        "data" to destFile.absolutePath,
                        "title" to fileName,
                        "mimeType" to mimeType
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to copy shared file: ${e.message}", e)
            }
        }.start()
    }

    private fun getFileNameFromUri(uri: Uri): String? {
        var name: String? = null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                name = cursor.getString(nameIndex)
            }
        }
        return name
    }

    private fun launchDirectoryPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, REQUEST_PICK_DIRECTORY)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_PICK_DIRECTORY) return

        val result = pendingResult
        val destPath = pendingDestPath
        pendingResult = null
        pendingDestPath = null

        if (result == null || destPath == null) return

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            Log.d(TAG, "User cancelled directory picker")
            result.success(mapOf("cancelled" to true, "copied" to 0, "total" to 0))
            return
        }

        val treeUri = data.data!!

        // Take persistable permission so we can access the tree.
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            Log.d(TAG, "Persisted URI permission for: $treeUri")
        } catch (e: SecurityException) {
            Log.e(TAG, "Failed to persist URI permission: ${e.message}")
            result.error("PERMISSION_ERROR", "Could not persist directory access: ${e.message}", null)
            return
        }

        // Copy files in a background thread.
        Thread {
            copyFromTreeUri(treeUri, destPath, result)
        }.start()
    }

    private fun copyFromTreeUri(treeUri: Uri, destPath: String, result: MethodChannel.Result) {
        try {
            val treeDoc = DocumentFile.fromTreeUri(this, treeUri)
            if (treeDoc == null || !treeDoc.exists()) {
                Log.w(TAG, "Tree document does not exist")
                runOnUiThread { result.success(mapOf("cancelled" to false, "copied" to 0, "total" to 0)) }
                return
            }

            Log.d(TAG, "Tree name: ${treeDoc.name}, children: ${treeDoc.listFiles().size}")

            val destDir = File(destPath)
            if (!destDir.exists()) destDir.mkdirs()

            var total = 0
            var copied = 0

            fun copyRecursive(dir: DocumentFile) {
                for (child in dir.listFiles()) {
                    if (child.isDirectory) {
                        copyRecursive(child)
                    } else if (child.isFile) {
                        val name = child.name ?: continue
                        val lower = name.lowercase()
                        if (lower.endsWith(".pdf") || lower.endsWith(".epub")) {
                            total++
                            val destFile = File(destDir, name)
                            try {
                                val inputStream =
                                    contentResolver.openInputStream(child.uri) ?: continue
                                inputStream.use { input ->
                                    destFile.outputStream().use { output ->
                                        input.copyTo(output)
                                    }
                                }
                                copied++
                                Log.d(TAG, "Copied: $name")
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to copy $name: ${e.message}")
                            }
                        }
                    }
                }
            }

            copyRecursive(treeDoc)
            Log.d(TAG, "copyFromTreeUri done: $copied/$total")

            runOnUiThread {
                result.success(mapOf("cancelled" to false, "copied" to copied, "total" to total))
            }
        } catch (e: Exception) {
            Log.e(TAG, "copyFromTreeUri error: ${e.message}", e)
            runOnUiThread { result.error("COPY_ERROR", e.message, null) }
        }
    }
}
