package com.example.shaladarpan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nativePrint: RajshalaNativePrint? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativePrint = RajshalaNativePrint(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        nativePrint?.dispose()
        nativePrint = null
        super.onDestroy()
    }
}
