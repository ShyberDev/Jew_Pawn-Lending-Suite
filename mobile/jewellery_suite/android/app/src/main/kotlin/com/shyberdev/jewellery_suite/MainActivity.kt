package com.shyberdev.jewellery_suite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
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
    }
}
