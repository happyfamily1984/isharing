package com.happyfamily.familylocator

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** 재부팅하거나 앱이 업데이트되면, 위치 공유를 켜 두었던 경우 다시 시작한다. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!LocationTrackingService.isEnabled(context)) return
        try {
            LocationTrackingService.start(context)
        } catch (e: Exception) {
            Log.e("BootReceiver", "could not restart location sharing", e)
        }
    }
}
