package com.hirumisu.musicapp

import android.app.Service
import android.content.Intent
import android.os.IBinder

class MetrolistPlaybackService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (MetrolistNativePlayer.shouldKeepForegroundService()) {
            MetrolistNativePlayer.promoteToForeground(this)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val keepAlive = MetrolistNativePlayer.shouldKeepForegroundService()
        when (intent?.action) {
            MetrolistNativePlayer.ACTION_SERVICE_STOP_FOREGROUND -> {
                if (keepAlive) {
                    // Ignore a stale stop request generated during a transient
                    // ExoPlayer state change; playback still expects to continue.
                    MetrolistNativePlayer.promoteToForeground(this)
                } else {
                    MetrolistNativePlayer.stopForegroundService(this)
                    stopSelf(startId)
                }
            }
            else -> {
                if (keepAlive) {
                    MetrolistNativePlayer.promoteToForeground(this)
                } else {
                    // A sticky restart after the process was actually reclaimed has
                    // no player state to protect. Do not violate Android's 5-second
                    // startForeground requirement by leaving an empty FGS pending.
                    stopSelf(startId)
                }
            }
        }
        return if (keepAlive) START_STICKY else START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (MetrolistNativePlayer.shouldKeepForegroundService()) {
            // Swiping the UI away must not stop an active music session.
            MetrolistNativePlayer.promoteToForeground(this)
        } else {
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }
}
