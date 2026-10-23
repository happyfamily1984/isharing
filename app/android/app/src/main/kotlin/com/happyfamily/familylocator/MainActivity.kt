package com.happyfamily.familylocator

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** 앱 화면이 보이는 중인지 (그때는 알림을 앱 화면 안에서 보여준다) */
        @Volatile
        var isVisible = false
            private set
    }

    // 벨이 울리는 중에 앱을 열었다면 폰을 찾은 것이므로 벨을 끈다.
    override fun onResume() {
        super.onResume()
        isVisible = true
        RingService.stopOnReaction(this)
    }

    override fun onPause() {
        isVisible = false
        super.onPause()
    }

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
                    // 벨이 울릴 때 화면 전체 안내 창(터치하면 끄기)을 띄우려면 필요
                    "canShowOverlay" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
                    )
                    "openOverlaySettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName"),
                                )
                            )
                        }
                        result.success(null)
                    }
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

        // 위치 공유 백그라운드 서비스 (앱을 닫아도 계속 동작)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "familylocator/tracking")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            LocationTrackingService.start(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "stop" -> {
                        LocationTrackingService.stop(this)
                        result.success(null)
                    }
                    "isRunning" -> result.success(LocationTrackingService.isRunning)
                    else -> result.notImplemented()
                }
            }
    }
}
