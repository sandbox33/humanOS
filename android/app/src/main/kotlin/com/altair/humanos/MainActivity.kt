package com.altair.humanos

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity is required by the health plugin (Health Connect
// permission contract).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceChannels.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
