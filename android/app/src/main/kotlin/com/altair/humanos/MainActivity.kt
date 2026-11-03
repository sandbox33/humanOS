package com.altair.humanos

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity is required by the health plugin (Health Connect
// permission contract).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceChannels.register(this, flutterEngine.dartExecutor.binaryMessenger)
        ContextBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
        LlmBridge.setUp(flutterEngine.dartExecutor.binaryMessenger, LlmBridgeImpl(applicationContext))
    }

    @Deprecated("Forwarded to the plugins by the superclass as well.")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        ContextBridge.onPermissionResult(requestCode)
    }
}
