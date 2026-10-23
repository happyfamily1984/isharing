package com.happyfamily.familylocator

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log

/**
 * 휴대폰 찾기 벨.
 * 알람 스트림(STREAM_ALARM)으로 재생하므로 벨소리 무음/진동 모드에서도 소리가 난다.
 * 재생 동안 알람 볼륨을 최대로 올렸다가 종료 시 원래 볼륨으로 되돌린다.
 *
 * 폰을 찾았다는 뜻이므로 화면을 켜거나 끄기(전원 버튼), 잠금 해제, 볼륨 버튼, 앱 열기 등
 * 어떤 반응이든 있으면 벨을 끈다.
 */
class RingService : Service() {

    companion object {
        const val ACTION_RING = "com.happyfamily.familylocator.RING"
        const val ACTION_STOP = "com.happyfamily.familylocator.STOP_RING"
        const val EXTRA_FROM_NAME = "fromName"

        private const val CHANNEL_RING = "ring"
        private const val CHANNEL_GENERAL = "general"
        private const val NOTIFICATION_ID = 7001
        private const val RING_DURATION_MS = 60_000L

        /** 벨이 울리기 시작한 직후의 화면 켜짐·볼륨 변경은 알림·볼륨 조절 때문일 수 있어 무시한다. */
        private const val REACTION_GRACE_MS = 3_000L

        private const val ACTION_VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"

        @Volatile
        private var ringStartedAt = 0L

        @Volatile
        var isRinging = false
            private set

        /** 사용자가 폰에 반응했을 때 (앱 열기 등) 울리는 중이면 끈다. */
        fun stopOnReaction(context: Context) {
            if (!isRinging || System.currentTimeMillis() - ringStartedAt < REACTION_GRACE_MS) return
            context.startService(Intent(context, RingService::class.java).setAction(ACTION_STOP))
        }

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_RING, "휴대폰 찾기 벨", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "그룹 멤버가 내 휴대폰 벨을 울릴 때 표시됩니다."
                    setSound(null, null) // 소리는 서비스에서 알람 스트림으로 직접 재생
                    enableVibration(false)
                }
            )
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_GENERAL, "일반 알림", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }

    private var player: MediaPlayer? = null
    private var originalAlarmVolume: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopSelf() }
    private var reactionReceiverRegistered = false

    /** 화면 켜기/끄기, 잠금 해제, 볼륨 버튼 → 폰을 찾은 것으로 보고 벨을 끈다. */
    private val reactionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (System.currentTimeMillis() - ringStartedAt < REACTION_GRACE_MS) return
            Log.i("RingService", "user reacted (${intent.action}); stopping ring")
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        ensureChannels(this)
        val fromName = intent?.getStringExtra(EXTRA_FROM_NAME).orEmpty()
        val notification = buildNotification(fromName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        if (!isRinging) startRinging()
        handler.removeCallbacks(autoStop)
        handler.postDelayed(autoStop, RING_DURATION_MS)
        return START_NOT_STICKY
    }

    private fun startRinging() {
        isRinging = true
        ringStartedAt = System.currentTimeMillis()
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            originalAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (e: SecurityException) {
            // 방해금지 모드 정책상 볼륨 변경이 막힌 기기: 현재 알람 볼륨으로 재생
            Log.w("RingService", "Cannot change alarm volume", e)
            originalAlarmVolume = null
        }

        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@RingService, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e("RingService", "Failed to play ring sound", e)
        }

        registerReactionReceiver()

        vibrator()?.let { v ->
            val pattern = longArrayOf(0, 800, 400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
        }
    }

    private fun registerReactionReceiver() {
        if (reactionReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(ACTION_VOLUME_CHANGED)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(reactionReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(reactionReceiver, filter)
            }
            reactionReceiverRegistered = true
        } catch (e: Exception) {
            Log.w("RingService", "Cannot watch for user reaction", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrator(): Vibrator? = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    private fun buildNotification(fromName: String): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val stopIntent = PendingIntent.getService(
            this, 0, Intent(this, RingService::class.java).setAction(ACTION_STOP), flags
        )
        val openIntent = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_RING)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        }
        val body = if (fromName.isBlank()) "벨이 울리고 있어요" else "${fromName}님이 벨을 울리고 있어요"
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("휴대폰 찾기")
            .setContentText(body)
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .setDeleteIntent(stopIntent)
            .addAction(Notification.Action.Builder(null, "벨 끄기", stopIntent).build())
            .build()
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStop)
        if (reactionReceiverRegistered) {
            try { unregisterReceiver(reactionReceiver) } catch (_: Exception) {}
            reactionReceiverRegistered = false
        }
        player?.run {
            try { stop() } catch (_: IllegalStateException) {}
            release()
        }
        player = null
        vibrator()?.cancel()
        originalAlarmVolume?.let { vol ->
            try {
                (getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                    .setStreamVolume(AudioManager.STREAM_ALARM, vol, 0)
            } catch (_: SecurityException) {}
        }
        isRinging = false
        super.onDestroy()
    }
}
