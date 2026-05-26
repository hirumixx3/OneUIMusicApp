package com.hirumisu.musicapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object AppSystemBridge {
    private const val DOWNLOAD_CHANNEL_ID = "com.hirumisu.musicapp.channel.downloads"
    private const val PLAYBACK_WAKE_LOCK_TAG = "com.hirumisu.musicapp:playback"

    private var appContext: Context? = null
    private var playbackWakeLock: PowerManager.WakeLock? = null

    fun initialize(context: Context) {
        appContext = context.applicationContext
        ensureChannels()
    }

    fun setPlaybackWakeLock(enabled: Boolean): Boolean {
        val context = appContext ?: return false
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        if (enabled) {
            val wakeLock = playbackWakeLock
                ?: powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, PLAYBACK_WAKE_LOCK_TAG).also {
                    it.setReferenceCounted(false)
                    playbackWakeLock = it
                }
            if (!wakeLock.isHeld) {
                wakeLock.acquire(10 * 60 * 60 * 1000L)
            }
        } else {
            playbackWakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        }
        return true
    }

    fun showDownloadProgress(
        id: String,
        title: String,
        subtitle: String,
        progress: Int,
        indeterminate: Boolean
    ): Boolean {
        val context = appContext ?: return false
        ensureChannels()
        val notification = NotificationCompat.Builder(context, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (title.isBlank()) "Baixando música" else title)
            .setContentText(if (subtitle.isBlank()) "Baixando..." else subtitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress.coerceIn(0, 100), indeterminate)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(buildLaunchIntent(context))
            .build()
        NotificationManagerCompat.from(context).notify(downloadNotificationId(id), notification)
        return true
    }

    fun completeDownload(id: String, title: String, subtitle: String, path: String): Boolean {
        val context = appContext ?: return false
        ensureChannels()
        val body = buildString {
            if (subtitle.isNotBlank()) append(subtitle)
            if (path.isNotBlank()) {
                if (isNotEmpty()) append(" • ")
                append(path)
            }
        }
        val notification = NotificationCompat.Builder(context, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(if (title.isBlank()) "Download concluído" else title)
            .setContentText(if (body.isBlank()) "Download concluído" else body)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, false)
            .setContentIntent(buildLaunchIntent(context))
            .build()
        NotificationManagerCompat.from(context).notify(downloadNotificationId(id), notification)
        return true
    }

    fun failDownload(id: String, title: String, subtitle: String, error: String): Boolean {
        val context = appContext ?: return false
        ensureChannels()
        val body = buildString {
            if (subtitle.isNotBlank()) append(subtitle)
            if (error.isNotBlank()) {
                if (isNotEmpty()) append(" • ")
                append(error)
            }
        }
        val notification = NotificationCompat.Builder(context, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(if (title.isBlank()) "Falha no download" else title)
            .setContentText(if (body.isBlank()) "Falha no download" else body)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(buildLaunchIntent(context))
            .build()
        NotificationManagerCompat.from(context).notify(downloadNotificationId(id), notification)
        return true
    }

    fun cancelDownload(id: String): Boolean {
        val context = appContext ?: return false
        NotificationManagerCompat.from(context).cancel(downloadNotificationId(id))
        return true
    }

    private fun ensureChannels() {
        val context = appContext ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val downloadsChannel = NotificationChannel(
            DOWNLOAD_CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Progresso dos downloads de músicas"
            setShowBadge(false)
        }
        manager.createNotificationChannel(downloadsChannel)
    }

    private fun buildLaunchIntent(context: Context): PendingIntent? {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, 2031, launchIntent, flags)
    }

    private fun downloadNotificationId(id: String): Int = 700000 + id.hashCode().absoluteValue % 100000
}

private val Int.absoluteValue: Int
    get() = if (this == Int.MIN_VALUE) 0 else kotlin.math.abs(this)
