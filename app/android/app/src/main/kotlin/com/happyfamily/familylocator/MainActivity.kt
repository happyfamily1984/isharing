package com.happyfamily.familylocator

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RingService.ensureChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "familylocator/ring")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "stop" -> {
                        startService(Intent(this, RingService::class.java).setAction(RingService.ACTION_STOP))
                        result.success(null)
                    }
                    "isRinging" -> result.success(RingService.isRinging)
                    else -> result.notImplemented()
                }
            }
    }
}
