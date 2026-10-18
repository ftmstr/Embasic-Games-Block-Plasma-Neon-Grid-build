package com.embasicgames.block_plasma_neon_grid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val storageChannel =
        "com.embasicgames.block_plasma_neon_grid/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "appFilesDir" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
