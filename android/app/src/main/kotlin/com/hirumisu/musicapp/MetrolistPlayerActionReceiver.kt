package com.hirumisu.musicapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MetrolistPlayerActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        MetrolistNativePlayer.handleNotificationAction(context.applicationContext, intent?.action.orEmpty())
    }
}
