package com.happyfamily.familylocator

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * FCM 메시지 브로드캐스트를 직접 수신한다. (firebase_messaging 플러그인의 리시버와 함께 동작)
 * data.type == "ring" 이면 앱이 종료된 상태여도 RingService 를 띄워 벨을 울린다.
 * 높은 우선순위(high priority) FCM 수신 직후에는 백그라운드에서도 포그라운드 서비스 시작이 허용된다.
 */
class RingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        if (extras.getString("type") != "ring") return

        val serviceIntent = Intent(context, RingService::class.java)
            .setAction(RingService.ACTION_RING)
            .putExtra(RingService.EXTRA_FROM_NAME, extras.getString("fromName") ?: "")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e("RingReceiver", "Failed to start RingService", e)
        }
    }
}
