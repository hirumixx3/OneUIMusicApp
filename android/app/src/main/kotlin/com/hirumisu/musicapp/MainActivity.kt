package com.hirumisu.musicapp

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : AudioServiceActivity() {
    private val channelName                = "fast_audio_scanner"
    private val equalizerChannelName       = "com.hirumisu.musicapp/equalizer"
    private val systemChannelName          = "com.hirumisu.musicapp/system"
    private val metrolistStreamChannelName = "com.hirumisu.musicapp/metrolist_stream"
    private val mainHandler                = Handler(Looper.getMainLooper())

    // Pending MethodChannel result for the Google-login flow
    private var pendingLoginResult: MethodChannel.Result? = null
    private val RC_GOOGLE_LOGIN = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Restore the full Metrolist/Innertube session on startup
        restorePersistedCookie()

        AppSystemBridge.initialize(applicationContext)

        // ── scanner channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAllAudioFilesJson" -> runAsync(result, "SCAN_ERROR") {
                        FastAudioScanner.scan(this)
                    }
                    "getAllAudioFilesJsonFile" -> runAsync(result, "SCAN_FILE_ERROR") {
                        FastAudioScanner.scanToCacheFile(this)
                    }
                    "getArtworkBase64" -> {
                        val uri     = call.argument<String>("uri")     ?: ""
                        val path    = call.argument<String>("path")    ?: ""
                        val albumId = call.argument<String>("albumId") ?: ""
                        runAsync(result, "ARTWORK_ERROR") {
                            FastAudioScanner.readArtworkBase64(this, uri, albumId, path)
                        }
                    }
                    "ensurePlayableFilePath" -> {
                        val id       = call.argument<String>("id")       ?: ""
                        val uri      = call.argument<String>("uri")      ?: ""
                        val path     = call.argument<String>("path")     ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: ""
                        val title    = call.argument<String>("title")    ?: ""
                        runAsync(result, "PLAYABLE_PATH_ERROR") {
                            FastAudioScanner.ensurePlayableFilePath(this, id, uri, path, mimeType, title)
                        }
                    }
                    "getLyrics" -> {
                        val uri    = call.argument<String>("uri")    ?: ""
                        val path   = call.argument<String>("path")   ?: ""
                        val title  = call.argument<String>("title")  ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val album  = call.argument<String>("album")  ?: ""
                        runAsync(result, "LYRICS_ERROR") {
                            FastAudioScanner.readLyricsOnDemand(this, uri, path, title, artist, album)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── equalizer channel ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, equalizerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported"         -> runAsync(result, "EQUALIZER_ERROR") { AppEqualizer.isSupported() }
                    "getState"            -> runAsync(result, "EQUALIZER_ERROR") { AppEqualizer.getState() }
                    "attachToAudioSession" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: -1
                        runAsync(result, "EQUALIZER_ERROR") { AppEqualizer.attachToSession(sessionId) }
                    }
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        runAsync(result, "EQUALIZER_ERROR") { AppEqualizer.setEnabled(enabled) }
                    }
                    "setBandLevel" -> {
                        val band  = call.argument<Int>("band")  ?: 0
                        val level = call.argument<Int>("level") ?: 0
                        runAsync(result, "EQUALIZER_ERROR") { AppEqualizer.setBandLevel(band, level) }
                    }
                    "reset"  -> runAsync(result, "EQUALIZER_ERROR") { AppEqualizer.reset() }
                    else     -> result.notImplemented()
                }
            }

        // ── Metrolist / online channel ────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, metrolistStreamChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── streaming ──────────────────────────────────────────────
                    "resolveStream" -> {
                        val videoId      = call.argument<String>("videoId")      ?: ""
                        val quality      = call.argument<String>("quality")      ?: "AUTO"
                        val forceRefresh = call.argument<Boolean>("forceRefresh") ?: false
                        runAsync(result, "METROLIST_STREAM_ERROR") {
                            MetrolistStreamResolver.resolve(applicationContext, videoId, quality, forceRefresh)
                        }
                    }
                    "prewarmStream" -> {
                        val videoId = call.argument<String>("videoId") ?: ""
                        val quality = call.argument<String>("quality") ?: "AUTO"
                        runAsync(result, "METROLIST_PREWARM_ERROR") {
                            MetrolistStreamResolver.prewarm(applicationContext, videoId, quality)
                        }
                    }
                    "nativePlay" -> {
                        val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                        runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                            MetrolistNativePlayer.play(applicationContext, args)
                        }
                    }
                    "nativePause" -> runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                        MetrolistNativePlayer.pause()
                    }
                    "nativeResume" -> runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                        MetrolistNativePlayer.resume()
                    }
                    "nativeSeek" -> {
                        val rawPosition = call.argument<Any>("positionMs")
                        val positionMs = when (rawPosition) {
                            is Number -> rawPosition.toLong()
                            is String -> rawPosition.toLongOrNull() ?: 0L
                            else -> 0L
                        }
                        runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                            MetrolistNativePlayer.seek(positionMs)
                        }
                    }
                    "nativeStop" -> runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                        MetrolistNativePlayer.stop()
                    }
                    "nativeState" -> runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                        MetrolistNativePlayer.state()
                    }
                    "nativeInvalidate" -> {
                        val videoId = call.argument<String>("videoId") ?: ""
                        runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                            MetrolistNativePlayer.invalidate(videoId)
                        }
                    }
                    "nativeUpdateOptions" -> {
                        val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                        runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                            MetrolistNativePlayer.updateOptions(args)
                        }
                    }
                    "nativeNext" -> runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                        MetrolistNativePlayer.skipToNext()
                    }
                    "nativePrevious" -> runOnMain(result, "METROLIST_NATIVE_PLAYER_ERROR") {
                        MetrolistNativePlayer.skipToPrevious()
                    }

                    // ── catalog ────────────────────────────────────────────────
                    "home" -> runAsync(result, "METROLIST_HOME_ERROR") {
                        MetrolistOnlineBridge.home(applicationContext)
                    }
                    "search" -> {
                        val query = call.argument<String>("query") ?: ""
                        runAsync(result, "METROLIST_SEARCH_ERROR") {
                            MetrolistOnlineBridge.search(applicationContext, query)
                        }
                    }
                    "searchSongs" -> {
                        val query = call.argument<String>("query") ?: ""
                        runAsync(result, "METROLIST_SEARCH_SONGS_ERROR") {
                            MetrolistOnlineBridge.searchSongs(applicationContext, query)
                        }
                    }
                    "searchAlbums" -> {
                        val query = call.argument<String>("query") ?: ""
                        runAsync(result, "METROLIST_SEARCH_ALBUMS_ERROR") {
                            MetrolistOnlineBridge.searchAlbums(applicationContext, query)
                        }
                    }
                    "searchArtists" -> {
                        val query = call.argument<String>("query") ?: ""
                        runAsync(result, "METROLIST_SEARCH_ARTISTS_ERROR") {
                            MetrolistOnlineBridge.searchArtists(applicationContext, query)
                        }
                    }
                    "searchPlaylists" -> {
                        val query = call.argument<String>("query") ?: ""
                        runAsync(result, "METROLIST_SEARCH_PLAYLISTS_ERROR") {
                            MetrolistOnlineBridge.searchPlaylists(applicationContext, query)
                        }
                    }
                    "fetchPersonalizedPlaylists" -> {
                        val queries = call.argument<List<String>>("queries") ?: emptyList()
                        runAsync(result, "METROLIST_PLAYLISTS_ERROR") {
                            MetrolistOnlineBridge.fetchPersonalizedPlaylists(applicationContext, queries)
                        }
                    }
                    "album" -> {
                        val browseId = call.argument<String>("browseId") ?: ""
                        runAsync(result, "METROLIST_ALBUM_ERROR") {
                            MetrolistOnlineBridge.album(applicationContext, browseId)
                        }
                    }
                    "artist" -> {
                        val browseId = call.argument<String>("browseId") ?: ""
                        runAsync(result, "METROLIST_ARTIST_ERROR") {
                            MetrolistOnlineBridge.artist(applicationContext, browseId)
                        }
                    }
                    "artistSongs" -> {
                        val artistName     = call.argument<String>("artistName")     ?: ""
                        val artistBrowseId = call.argument<String>("artistBrowseId") ?: ""
                        val moreBrowseId   = call.argument<String?>("moreBrowseId")
                        val moreParams     = call.argument<String?>("moreParams")
                        runAsync(result, "METROLIST_ARTIST_SONGS_ERROR") {
                            MetrolistOnlineBridge.artistSongs(applicationContext, artistName, artistBrowseId, moreBrowseId, moreParams)
                        }
                    }
                    "artistAlbums" -> {
                        val artistName     = call.argument<String>("artistName")     ?: ""
                        val artistBrowseId = call.argument<String>("artistBrowseId") ?: ""
                        val moreBrowseId   = call.argument<String?>("moreBrowseId")
                        val moreParams     = call.argument<String?>("moreParams")
                        runAsync(result, "METROLIST_ARTIST_ALBUMS_ERROR") {
                            MetrolistOnlineBridge.artistAlbums(applicationContext, artistName, artistBrowseId, moreBrowseId, moreParams)
                        }
                    }
                    "playlist" -> {
                        val playlistId = call.argument<String>("playlistId") ?: ""
                        runAsync(result, "METROLIST_PLAYLIST_ERROR") {
                            MetrolistOnlineBridge.playlist(applicationContext, playlistId)
                        }
                    }
                    "lyrics" -> {
                        val title      = call.argument<String>("title")   ?: ""
                        val artist     = call.argument<String>("artist")  ?: ""
                        val album      = call.argument<String>("album")   ?: ""
                        val durationMs = call.argument<Int>("durationMs") ?: 0
                        runAsync(result, "METROLIST_LYRICS_ERROR") {
                            MetrolistOnlineBridge.lyrics(applicationContext, title, artist, album, durationMs)
                        }
                    }

                    // ── account / login ────────────────────────────────────────
                    "loginWithGoogle" -> {
                        pendingLoginResult = result
                        startActivityForResult(
                            Intent(this, GoogleLoginActivity::class.java),
                            RC_GOOGLE_LOGIN,
                        )
                        // result delivered in onActivityResult
                    }
                    "logoutGoogle" -> {
                        MetrolistYouTubeSession.clearAccount(applicationContext)
                        result.success(true)
                    }
                    "getGoogleAccount" -> {
                        val prefs = getSharedPreferences("metrolist_prefs", MODE_PRIVATE)
                        val cookie = prefs.getString("yt_cookie", null)
                        if (cookie.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            result.success(mapOf(
                                "name"  to (prefs.getString("account_name",  "") ?: ""),
                                "email" to (prefs.getString("account_email", "") ?: ""),
                                "photo" to (prefs.getString("account_photo", "") ?: ""),
                            ))
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // ── system channel ────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setPlaybackWakeLock" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runAsync(result, "SYSTEM_ERROR") { AppSystemBridge.setPlaybackWakeLock(enabled) }
                    }
                    "showDownloadProgress" -> {
                        val id            = call.argument<String>("id")           ?: "download"
                        val title         = call.argument<String>("title")        ?: ""
                        val subtitle      = call.argument<String>("subtitle")     ?: ""
                        val progress      = call.argument<Int>("progress")        ?: 0
                        val indeterminate = call.argument<Boolean>("indeterminate") ?: true
                        runAsync(result, "SYSTEM_ERROR") {
                            AppSystemBridge.showDownloadProgress(id, title, subtitle, progress, indeterminate)
                        }
                    }
                    "completeDownload" -> {
                        val id       = call.argument<String>("id")       ?: "download"
                        val title    = call.argument<String>("title")    ?: ""
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val path     = call.argument<String>("path")     ?: ""
                        runAsync(result, "SYSTEM_ERROR") { AppSystemBridge.completeDownload(id, title, subtitle, path) }
                    }
                    "failDownload" -> {
                        val id       = call.argument<String>("id")       ?: "download"
                        val title    = call.argument<String>("title")    ?: ""
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val error    = call.argument<String>("error")    ?: ""
                        runAsync(result, "SYSTEM_ERROR") { AppSystemBridge.failDownload(id, title, subtitle, error) }
                    }
                    "cancelDownload" -> {
                        val id = call.argument<String>("id") ?: "download"
                        runAsync(result, "SYSTEM_ERROR") { AppSystemBridge.cancelDownload(id) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Called when GoogleLoginActivity finishes
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == RC_GOOGLE_LOGIN) {
            val pending = pendingLoginResult ?: return
            pendingLoginResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                val cookie = data.getStringExtra(GoogleLoginActivity.RESULT_COOKIE) ?: ""
                val name   = data.getStringExtra(GoogleLoginActivity.RESULT_ACCOUNT_NAME)  ?: ""
                val email  = data.getStringExtra(GoogleLoginActivity.RESULT_ACCOUNT_EMAIL) ?: ""
                val photo  = data.getStringExtra(GoogleLoginActivity.RESULT_ACCOUNT_PHOTO) ?: ""
                pending.success(mapOf(
                    "cookie" to cookie,
                    "name"   to name,
                    "email"  to email,
                    "photo"  to photo,
                ))
            } else {
                pending.success(null) // user cancelled
            }
        }
    }

    /** Re-apply the saved Metrolist/Innertube session so streams work after restart. */
    private fun restorePersistedCookie() {
        MetrolistYouTubeSession.restore(applicationContext, blockForVisitor = false)
    }

    private fun runOnMain(result: MethodChannel.Result, errorCode: String, block: () -> Any?) {
        val action = {
            try {
                result.success(block())
            } catch (e: Exception) {
                result.error(errorCode, e.message ?: e.javaClass.simpleName, null)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post { action() }
        }
    }

    private fun runAsync(result: MethodChannel.Result, errorCode: String, block: () -> Any?) {
        thread(start = true, isDaemon = true) {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error(errorCode, e.message, null) }
            }
        }
    }
}
