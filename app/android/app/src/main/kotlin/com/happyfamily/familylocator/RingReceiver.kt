package com.happyfamily.familylocator

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * FCM 메시지 브로드캐스트를 직접 수신한다. (firebase_messaging 플러그인의 리시버와 함께 동작)
 * data.type == "ring" 이면 앱이 종료된 상태여도 RingService 를 띄워 벨을 울린다.
 * data.timeoutMs 가 있는 알림(거리 알림)은 직접 띄우고 그 시간이 지나면 알림창에서 지운다.
 * 높은 우선순위(high priority) FCM 수신 직후에는 백그라운드에서도 포그라운드 서비스 시작이 허용된다.
 */
class RingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        if (extras.getString("timeoutMs") != null) {
            showTimedAlert(context, extras)
            return
        }
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

    /** 잠깐만 보이는 알림. 앱이 열려 있으면 앱 화면 안에서 보여주므로 띄우지 않는다. */
    private fun showTimedAlert(context: Context, extras: Bundle) {
        if (MainActivity.isVisible) return
        val title = extras.getString("title") ?: return
        val body = extras.getString("body") ?: ""
        val timeoutMs = extras.getString("timeoutMs")?.toLongOrNull() ?: 15_000L
        RingService.ensureChannels(context)
        val openApp = PendingIntent.getActivity(
            context, 3,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, "general").setTimeoutAfter(timeoutMs)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        manager.notify(id, notification)
        // Android 8 미만은 setTimeoutAfter 가 없어 직접 지운다.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Handler(Looper.getMainLooper()).postDelayed({ manager.cancel(id) }, timeoutMs)
        }
    }
}
