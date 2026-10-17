package com.happyfamily.familylocator

import android.content.Intent
import android.os.Build
import android.os.PowerManager
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
        // 배터리 최적화(절전) 대상이면 백그라운드에서 위치 공유가 멈출 수 있어 앱에서 안내한다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "familylocator/power")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBatteryOptimized" -> {
                        val optimized = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            val ignoring = pm.isIgnoringBatteryOptimizations(packageName)
                            ignoring.not()
                        } else {
                            false
                        }
                        result.success(optimized)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
