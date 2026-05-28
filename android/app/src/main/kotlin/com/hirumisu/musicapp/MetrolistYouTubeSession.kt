package com.hirumisu.musicapp

import android.content.Context
import com.metrolist.innertube.YouTube
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import timber.log.Timber
import kotlin.concurrent.thread

/**
 * Restores the same YouTube session pieces that the original Metrolist app keeps
 * alive before calling Innertube/player endpoints.
 *
 * The streaming code needs visitorData/dataSyncId for WEB_REMIX PoToken requests.
 * Without this, Innertube can return player responses with no usable stream URL.
 */
object MetrolistYouTubeSession {
    private const val TAG = "MetrolistSession"
    private const val PREFS = "metrolist_prefs"
    private const val KEY_COOKIE = "yt_cookie"
    private const val KEY_VISITOR_DATA = "visitor_data"
    private const val KEY_DATA_SYNC_ID = "data_sync_id"

    @Volatile private var restored = false
    @Volatile private var visitorLoadStarted = false

    fun restore(context: Context, blockForVisitor: Boolean = false) {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val cookie = prefs.getString(KEY_COOKIE, null)?.takeIf { it.isNotBlank() && it != "null" }
        YouTube.cookie = cookie

        val dataSyncId = normalizeDataSyncId(prefs.getString(KEY_DATA_SYNC_ID, null))
        if (!dataSyncId.isNullOrBlank()) YouTube.dataSyncId = dataSyncId

        val visitorData = prefs.getString(KEY_VISITOR_DATA, null)?.takeIf { it.isNotBlank() && it != "null" }
        if (!visitorData.isNullOrBlank()) YouTube.visitorData = visitorData

        restored = true

        if (YouTube.visitorData.isNullOrBlank()) {
            if (blockForVisitor) {
                ensureVisitorData(app)
            } else {
                ensureVisitorDataAsync(app)
            }
        }
    }

    fun ensureVisitorData(context: Context): String? {
        val current = YouTube.visitorData?.takeIf { it.isNotBlank() && it != "null" }
        if (current != null) return current
        return synchronized(this) {
            val existing = YouTube.visitorData?.takeIf { it.isNotBlank() && it != "null" }
            if (existing != null) return@synchronized existing

            val app = context.applicationContext
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val stored = prefs.getString(KEY_VISITOR_DATA, null)?.takeIf { it.isNotBlank() && it != "null" }
            if (stored != null) {
                YouTube.visitorData = stored
                return@synchronized stored
            }

            val fetched = runCatching {
                runBlocking(Dispatchers.IO) { YouTube.visitorData().getOrNull() }
            }.getOrNull()?.takeIf { it.isNotBlank() && it != "null" }

            if (fetched != null) {
                YouTube.visitorData = fetched
                prefs.edit().putString(KEY_VISITOR_DATA, fetched).apply()
                Timber.tag(TAG).d("visitorData carregado para Innertube")
            } else {
                Timber.tag(TAG).w("Não foi possível carregar visitorData")
            }
            fetched
        }
    }

    fun ensureVisitorDataAsync(context: Context) {
        if (visitorLoadStarted || !YouTube.visitorData.isNullOrBlank()) return
        visitorLoadStarted = true
        val app = context.applicationContext
        thread(start = true, isDaemon = true, name = "MetrolistVisitorData") {
            try {
                ensureVisitorData(app)
            } finally {
                visitorLoadStarted = false
            }
        }
    }

    fun saveCookie(context: Context, rawCookie: String, name: String = "", email: String = "", photo: String = "") {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        YouTube.cookie = rawCookie.takeIf { it.isNotBlank() }
        prefs.edit()
            .putString(KEY_COOKIE, rawCookie)
            .putString("account_name", name)
            .putString("account_email", email)
            .putString("account_photo", photo)
            .apply()
        ensureVisitorDataAsync(app)
    }

    fun clearAccount(context: Context) {
        val app = context.applicationContext
        YouTube.cookie = null
        YouTube.dataSyncId = null
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_COOKIE)
            .remove(KEY_DATA_SYNC_ID)
            .remove("account_name")
            .remove("account_email")
            .remove("account_photo")
            .apply()
    }

    private fun normalizeDataSyncId(value: String?): String? {
        val raw = value?.takeIf { it.isNotBlank() && it != "null" } ?: return null
        return when {
            !raw.contains("||") -> raw
            raw.endsWith("||") -> raw.substringBefore("||")
            else -> raw.substringAfter("||")
        }.takeIf { it.isNotBlank() }
    }
}
