package com.shyberdev.jewellery_suite

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Two small platform bridges:
 *
 * * `app_info` — the installed APK's real size for the About screen (#039).
 * * `backup_files` — Android's own "save as" / "open" pickers, so a backup can
 *   leave the app (Downloads, Drive, USB) and come back after a reinstall.
 *   Both use the Storage Access Framework, which grants access to the one file
 *   the shopkeeper picked. No storage permission is declared or needed (#029).
 */
class MainActivity : FlutterActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportSource: String? = null
    private var importResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.shyberdev.jewellery_suite/app_info"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "apkSizeBytes" -> {
                    try {
                        // sourceDir is the installed APK path. Its length is
                        // the real package size the About screen displays.
                        result.success(File(applicationInfo.sourceDir).length())
                    } catch (e: Exception) {
                        result.error("apk_size", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.shyberdev.jewellery_suite/backup_files"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportBackup" -> startExport(call.argument<String>("path"),
                    call.argument<String>("name"), result)
                "pickBackup" -> startImport(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun startExport(path: String?, name: String?, result: MethodChannel.Result) {
        if (exportResult != null) {
            result.error("busy", "A save dialog is already open.", null)
            return
        }
        if (path == null || !File(path).exists()) {
            result.error("missing", "The backup file no longer exists.", null)
            return
        }
        exportResult = result
        exportSource = path
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_TITLE, name ?: "jewellery-suite-backup.zip")
        }
        try {
            startActivityForResult(intent, REQ_EXPORT)
        } catch (e: Exception) {
            exportResult = null
            exportSource = null
            result.error("backup_export", e.message, null)
        }
    }

    private fun startImport(result: MethodChannel.Result) {
        if (importResult != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        importResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_MIME_TYPES,
                arrayOf("application/zip", "application/octet-stream"))
        }
        try {
            startActivityForResult(intent, REQ_IMPORT)
        } catch (e: Exception) {
            importResult = null
            result.error("backup_import", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_EXPORT) {
            val result = exportResult ?: return
            val source = exportSource
            exportResult = null
            exportSource = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null || source == null) {
                result.success("cancelled")
                return
            }
            try {
                contentResolver.openOutputStream(uri)?.use { out ->
                    File(source).inputStream().use { input -> input.copyTo(out) }
                } ?: throw IllegalStateException("The chosen file could not be opened.")
                result.success("saved")
            } catch (e: Exception) {
                result.error("backup_export", e.message, null)
            }
            return
        }
        if (requestCode == REQ_IMPORT) {
            val result = importResult ?: return
            importResult = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            try {
                val dir = File(cacheDir, "imports").apply { mkdirs() }
                val target = File(dir, "restore-${System.currentTimeMillis()}.zip")
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { out -> input.copyTo(out) }
                } ?: throw IllegalStateException("The chosen file could not be read.")
                result.success(target.absolutePath)
            } catch (e: Exception) {
                result.error("backup_import", e.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private companion object {
        const val REQ_EXPORT = 7101
        const val REQ_IMPORT = 7102
    }
}
