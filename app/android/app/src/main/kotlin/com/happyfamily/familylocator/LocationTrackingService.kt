package com.happyfamily.familylocator

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.Executors

/**
 * 위치 공유 포그라운드 서비스.
 *
 * Flutter 화면과 별도로 동작하므로 최근 앱 목록에서 앱을 밀어서 닫거나 화면이 정리돼도
 * 계속 위치를 올린다. 재부팅·앱 업데이트 후에는 BootReceiver 가 다시 시작한다.
 *
 * 앱(Dart)의 LocationService 와 같은 규칙으로 저장한다:
 * - users/{uid}.lastLocation / updatedAt / battery / charging : 최신 위치
 * - users/{uid}/locations : 이동경로 (30m 이상 이동 또는 5분마다, 오차 80m 이하만)
 */
class LocationTrackingService : Service() {

    companion object {
        private const val TAG = "LocationTracking"
        private const val CHANNEL_ID = "location_sharing"
        private const val NOTIFICATION_ID = 7002
        private const val PREFS = "location_tracking"
        private const val KEY_ENABLED = "enabled"

        private const val INTERVAL_MS = 15_000L
        private const val MIN_DISTANCE_M = 10f
        private const val HEARTBEAT_MS = 5 * 60 * 1000L
        private const val HISTORY_MIN_DISTANCE_M = 30f
        private const val HISTORY_MAX_ACCURACY_M = 80f
        private const val GOOD_ACCURACY_M = 100f

        @Volatile
        var isRunning = false
            private set

        /** 사용자가 위치 공유를 켜 두었는지 (재부팅 후 다시 시작할지 결정) */
        fun isEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

        private fun setEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_ENABLED, enabled).apply()
        }

        fun start(context: Context) {
            setEnabled(context, true)
            val intent = Intent(context, LocationTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            setEnabled(context, false)
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }

    private lateinit var fused: FusedLocationProviderClient
    private val handler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var started = false
    private var lastUploaded: Location? = null
    private var lastUploadAt = 0L
    private var lastHistory: Location? = null

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            onLocation(location, false)
        }
    }

    /** 움직이지 않아 위치 갱신이 없을 때도 5분마다 위치를 올려 온라인 상태와 머문 곳을 남긴다. */
    private val heartbeat = object : Runnable {
        override fun run() {
            if (System.currentTimeMillis() - lastUploadAt >= HEARTBEAT_MS - 10_000L) requestFreshLocation()
            handler.postDelayed(this, HEARTBEAT_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        fused = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (FirebaseAuth.getInstance().currentUser == null || !hasLocationPermission()) {
            Log.w(TAG, "not signed in or no location permission; stopping")
            setEnabled(this, false)
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // 백그라운드에서 시작이 막힌 경우 (일부 기기·Android 버전): 앱을 열면 다시 시작된다.
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return START_NOT_STICKY
        }
        if (!started) {
            started = true
            isRunning = true
            requestUpdates()
            requestFreshLocation()
            handler.postDelayed(heartbeat, HEARTBEAT_MS)
        }
        // 시스템이 서비스를 정리해도 다시 살려낸다.
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeat)
        try {
            fused.removeLocationUpdates(callback)
        } catch (_: Exception) {
        }
        io.shutdown()
        started = false
        isRunning = false
        super.onDestroy()
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun requestUpdates() {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, INTERVAL_MS)
            .setMinUpdateDistanceMeters(MIN_DISTANCE_M)
            .build()
        try {
            fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
        } catch (e: SecurityException) {
            Log.e(TAG, "location permission revoked", e)
            stopSelf()
        }
    }

    private fun requestFreshLocation() {
        try {
            fused.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
                .addOnSuccessListener { location ->
                    if (location != null) onLocation(location, true)
                }
        } catch (e: SecurityException) {
            Log.e(TAG, "location permission revoked", e)
        }
    }

    private fun onLocation(location: Location, force: Boolean) {
        // 서비스가 멈춘 뒤 늦게 도착한 위치는 버린다.
        if (!started || io.isShutdown) return
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid == null) {
            stopSelf()
            return
        }
        val now = System.currentTimeMillis()
        // 방금 올린 정확한 위치를 오차가 훨씬 큰 위치로 덮어쓰지 않는다.
        val previous = lastUploaded
        if (!force && previous != null &&
            location.accuracy > GOOD_ACCURACY_M &&
            location.accuracy > previous.accuracy * 2 &&
            now - lastUploadAt < 2 * 60 * 1000L
        ) {
            return
        }
        lastUploaded = location
        lastUploadAt = now

        val batteryManager = getSystemService(BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val charging = batteryManager.isCharging

        val lastPoint = lastHistory
        val moved = lastPoint == null || lastPoint.distanceTo(location) >= HISTORY_MIN_DISTANCE_M
        val addHistory = (moved || force) && location.accuracy <= HISTORY_MAX_ACCURACY_M
        if (addHistory) lastHistory = location

        io.execute {
            try {
                FirestoreRest.upload(uid, location, if (level in 0..100) level else null, charging, addHistory)
            } catch (e: Exception) {
                Log.w(TAG, "location upload failed", e)
            }
        }
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "위치 공유", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "가족에게 위치를 공유하는 동안 표시됩니다."
                    setShowBadge(false)
                }
            )
        }
        val openApp = PendingIntent.getActivity(
            this, 2,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("패밀리 위치 공유 중")
            .setContentText("그룹 멤버에게 내 위치를 공유하고 있어요. 앱에서 언제든 중지할 수 있어요.")
            .setOngoing(true)
            .setContentIntent(openApp)
            .build()
    }
}
