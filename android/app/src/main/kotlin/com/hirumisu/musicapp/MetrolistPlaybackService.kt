package com.hirumisu.musicapp

import android.app.Service
import android.content.Intent
import android.os.IBinder

class MetrolistPlaybackService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            MetrolistNativePlayer.ACTION_SERVICE_STOP_FOREGROUND -> {
                MetrolistNativePlayer.stopForegroundService(this)
                stopSelf(startId)
            }
            else -> {
                MetrolistNativePlayer.promoteToForeground(this)
            }
        }
        return START_STICKY
    }
}
