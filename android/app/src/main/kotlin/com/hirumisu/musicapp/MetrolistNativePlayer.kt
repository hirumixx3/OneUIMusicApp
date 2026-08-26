package com.hirumisu.musicapp

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.Service
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.DefaultExtractorsFactory
import com.metrolist.innertube.YouTube
import com.metrolist.music.constants.AudioQuality
import com.metrolist.music.utils.cipher.CipherDeobfuscator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request
import timber.log.Timber
import java.io.File
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/**
 * Único player nativo do app.
 *
 * Online: ExoPlayer -> ResolvingDataSource -> resolvedor nativo Metrolist/Innertube.
 * Local:  ExoPlayer -> DefaultDataSource -> file/content Uri.
 *
 * O Flutter só envia a fila e controla UI; a notificação Android controla o
 * próprio ExoPlayer nativo, com play/pause, próxima, anterior, repetir e aleatório.
 */
object MetrolistNativePlayer {
    private const val TAG = "MetrolistNativePlayer"
    private const val CHUNK_LENGTH = 512 * 1024L
    private const val CACHE_SAFETY_MS = 120_000L
    private const val CHANNEL_ID = "metrolist_native_playback"
    private const val NOTIFICATION_ID = 230101
    private const val ARTWORK_MAX_EDGE = 1024
    private const val ARTWORK_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"

    const val ACTION_PLAY_PAUSE = "com.hirumisu.musicapp.action.PLAY_PAUSE"
    const val ACTION_NEXT = "com.hirumisu.musicapp.action.NEXT"
    const val ACTION_PREVIOUS = "com.hirumisu.musicapp.action.PREVIOUS"
    const val ACTION_SHUFFLE = "com.hirumisu.musicapp.action.SHUFFLE"
    const val ACTION_REPEAT = "com.hirumisu.musicapp.action.REPEAT"
    const val ACTION_STOP = "com.hirumisu.musicapp.action.STOP"
    const val ACTION_SERVICE_START = "com.hirumisu.musicapp.action.SERVICE_START"
    const val ACTION_SERVICE_STOP_FOREGROUND = "com.hirumisu.musicapp.action.SERVICE_STOP_FOREGROUND"

    @Volatile private var appContext: Context? = null
    @Volatile private var player: ExoPlayer? = null
    @Volatile private var lastError: String? = null
    @Volatile private var currentQuality: AudioQuality = AudioQuality.AUTO
    @Volatile private var currentArtworkBitmap: Bitmap? = null
    @Volatile private var currentArtworkKey: String? = null
    @Volatile private var mediaSession: MediaSessionCompat? = null
    @Volatile private var lastNotification: Notification? = null
    @Volatile private var foregroundServiceActive = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val artExecutor = Executors.newSingleThreadExecutor()
    private val songUrlCache = ConcurrentHashMap<String, Pair<String, Long>>()
    private val playbackErrorRetries = ConcurrentHashMap<String, Int>()

    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .proxy(YouTube.proxy)
            .proxyAuthenticator { _, response ->
                YouTube.proxyAuth?.let { auth ->
                    response.request.newBuilder()
                        .header("Proxy-Authorization", auth)
                        .build()
                } ?: response.request
            }
            .build()
    }

    private fun <T> onMainSync(block: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        val valueRef = AtomicReference<T?>()
        val errorRef = AtomicReference<Throwable?>()
        val latch = CountDownLatch(1)
        mainHandler.post {
            try {
                valueRef.set(block())
            } catch (t: Throwable) {
                errorRef.set(t)
            } finally {
                latch.countDown()
            }
        }
        latch.await()
        errorRef.get()?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return valueRef.get() as T
    }

    private fun ensureInitialized(context: Context) {
        if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
        val app = context.applicationContext
        appContext = app
        createNotificationChannel(app)
        MetrolistYouTubeSession.restore(app, blockForVisitor = false)
        runCatching { CipherDeobfuscator.initialize(app) }
        ensureMediaSession(app)
    }

    private fun ensureMediaSession(context: Context): MediaSessionCompat {
        mediaSession?.let { return it }
        val session = MediaSessionCompat(context, "MetrolistNativePlayer")
        session.setCallback(object : MediaSessionCompat.Callback() {
            override fun onPlay() { resume() }
            override fun onPause() { pause() }
            override fun onSkipToNext() { skipToNext() }
            override fun onSkipToPrevious() { skipToPrevious() }
            override fun onSeekTo(pos: Long) { seek(pos) }
            override fun onStop() { stop() }
            override fun onCustomAction(action: String?, extras: Bundle?) {
                val context = appContext ?: return
                handleNotificationAction(context, action.orEmpty())
            }
            override fun onSetShuffleMode(shuffleMode: Int) {
                onMainSync {
                    player?.shuffleModeEnabled = shuffleMode != PlaybackStateCompat.SHUFFLE_MODE_NONE
                    appContext?.let { updateNotification(it) }
                }
            }
            override fun onSetRepeatMode(repeatMode: Int) {
                onMainSync {
                    player?.repeatMode = when (repeatMode) {
                        PlaybackStateCompat.REPEAT_MODE_ONE -> Player.REPEAT_MODE_ONE
                        PlaybackStateCompat.REPEAT_MODE_ALL,
                        PlaybackStateCompat.REPEAT_MODE_GROUP -> Player.REPEAT_MODE_ALL
                        else -> Player.REPEAT_MODE_OFF
                    }
                    appContext?.let { updateNotification(it) }
                }
            }
        })
        session.isActive = true
        mediaSession = session
        return session
    }

    private fun attachEqualizerToPlayerSession(nativePlayer: ExoPlayer?): Int {
        val audioSessionId = runCatching { nativePlayer?.audioSessionId ?: 0 }.getOrDefault(0)
        if (audioSessionId > 0) {
            runCatching { AppEqualizer.attachToSession(audioSessionId) }
                .onFailure { Timber.tag(TAG).w(it, "Falha ao anexar equalizador à sessão %s", audioSessionId) }
        }
        return audioSessionId
    }

    private fun ensureEqualizerForCurrentPlayer() {
        attachEqualizerToPlayerSession(player)
    }

    private fun resumePrepared(p: ExoPlayer) {
        if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
            runCatching { p.prepare() }
        }
        p.playWhenReady = true
        p.play()
    }

    private fun playMediaIndex(p: ExoPlayer, index: Int, positionMs: Long = 0L) {
        if (index < 0 || index >= p.mediaItemCount) return
        p.seekTo(index, positionMs.coerceAtLeast(0L))
        if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
            runCatching { p.prepare() }
        }
        p.playWhenReady = true
        p.play()
    }

    private fun recoverEndedPlayback(p: ExoPlayer, context: Context) {
        val runRecovery = {
            val current = player
            if (current == null || current !== p || current.mediaItemCount <= 0 || current.playbackState != Player.STATE_ENDED) {
                updateNotification(context.applicationContext)
            } else {
                when (current.repeatMode) {
                    Player.REPEAT_MODE_ONE -> {
                        val index = current.currentMediaItemIndex.coerceIn(0, current.mediaItemCount - 1)
                        playMediaIndex(current, index, 0L)
                    }
                    Player.REPEAT_MODE_ALL -> {
                        val next = current.nextMediaItemIndex.takeIf { it != C.INDEX_UNSET } ?: 0
                        playMediaIndex(current, next, 0L)
                    }
                    else -> {
                        // Em alguns aparelhos o ExoPlayer chega em ENDED sem fazer a transição automática.
                        // Se ainda existir próximo item na fila nativa, avance mesmo com o app em segundo plano.
                        val next = current.nextMediaItemIndex
                        if (next != C.INDEX_UNSET) playMediaIndex(current, next, 0L)
                    }
                }
                updateNotification(context.applicationContext)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) runRecovery() else mainHandler.post { runRecovery() }
    }

    private fun recoverPlaybackError(p: ExoPlayer, context: Context, mediaId: String) {
        val key = mediaId.ifBlank { p.currentMediaItem?.mediaId.orEmpty() }.ifBlank { "item:${p.currentMediaItemIndex}" }
        val attempt = playbackErrorRetries.merge(key, 1) { old, _ -> old + 1 } ?: 1
        mainHandler.postDelayed({
            val current = player ?: return@postDelayed
            if (current !== p || current.mediaItemCount <= 0) return@postDelayed
            if (attempt <= 1) {
                // Primeira falha: invalida cache, reabre o mesmo item e deixa o ExoPlayer resolver de novo.
                if (key.isNotBlank()) {
                    songUrlCache.remove(key)
                    MetrolistStreamResolver.invalidate(key)
                }
                val index = current.currentMediaItemIndex.coerceIn(0, current.mediaItemCount - 1)
                playMediaIndex(current, index, current.currentPosition.coerceAtLeast(0L))
            } else {
                when {
                    current.repeatMode == Player.REPEAT_MODE_ONE -> playMediaIndex(current, current.currentMediaItemIndex.coerceIn(0, current.mediaItemCount - 1), 0L)
                    current.nextMediaItemIndex != C.INDEX_UNSET -> playMediaIndex(current, current.nextMediaItemIndex, 0L)
                    current.repeatMode == Player.REPEAT_MODE_ALL && current.mediaItemCount > 0 -> playMediaIndex(current, 0, 0L)
                }
            }
            updateNotification(context.applicationContext)
        }, 650L)
    }

    private fun ensurePlayer(context: Context): ExoPlayer {
        check(Looper.myLooper() == Looper.getMainLooper()) { "MetrolistNativePlayer precisa rodar na main thread" }
        ensureInitialized(context)
        player?.let { return it }
        val created = ExoPlayer.Builder(context.applicationContext)
            .setLooper(Looper.getMainLooper())
            .setMediaSourceFactory(createMediaSourceFactory(context.applicationContext))
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true,
            )
            .setSeekBackIncrementMs(5000)
            .setSeekForwardIncrementMs(5000)
            .build()

        created.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                val mediaId = created.currentMediaItem?.mediaId.orEmpty()
                val streamKey = created.currentMediaItem?.localConfiguration?.customCacheKey.orEmpty()
                lastError = "${error.errorCodeName}: ${error.message ?: error.cause?.message ?: "erro"}"
                if (streamKey.isNotBlank()) songUrlCache.remove(streamKey)
                if (mediaId.isNotBlank()) {
                    songUrlCache.remove(mediaId)
                    MetrolistStreamResolver.invalidate(mediaId)
                }
                Timber.tag(TAG).e(error, "Erro no player nativo do Metrolist para %s", mediaId)
                recoverPlaybackError(created, context.applicationContext, mediaId.ifBlank { streamKey })
                updateNotification(context.applicationContext)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                Timber.tag(TAG).d(
                    "state=%s playing=%s playWhenReady=%s pos=%s mediaId=%s",
                    playbackState,
                    created.isPlaying,
                    created.playWhenReady,
                    created.currentPosition,
                    created.currentMediaItem?.mediaId,
                )
                if (playbackState == Player.STATE_READY) {
                    lastError = null
                    created.currentMediaItem?.mediaId?.let { playbackErrorRetries.remove(it) }
                    created.currentMediaItem?.localConfiguration?.customCacheKey?.let { playbackErrorRetries.remove(it) }
                }
                attachEqualizerToPlayerSession(created)
                if (playbackState == Player.STATE_ENDED) {
                    recoverEndedPlayback(created, context.applicationContext)
                }
                updateNotification(context.applicationContext)
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                attachEqualizerToPlayerSession(created)
                updateNotification(context.applicationContext)
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                currentArtworkBitmap = null
                currentArtworkKey = null
                lastError = null
                mediaItem?.mediaId?.let { playbackErrorRetries.remove(it) }
                mediaItem?.localConfiguration?.customCacheKey?.let { playbackErrorRetries.remove(it) }
                attachEqualizerToPlayerSession(created)
                updateNotification(context.applicationContext)
            }

            override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
                updateNotification(context.applicationContext)
            }

            override fun onRepeatModeChanged(repeatMode: Int) {
                updateNotification(context.applicationContext)
            }
        })
        player = created
        attachEqualizerToPlayerSession(created)
        return created
    }

    private fun createMediaSourceFactory(context: Context) =
        DefaultMediaSourceFactory(
            createDataSourceFactory(context),
            DefaultExtractorsFactory(),
        )

    private fun isDirectLocalOrHttp(dataSpecUri: Uri): Boolean {
        val scheme = dataSpecUri.scheme?.lowercase(Locale.US) ?: return false
        return scheme == "file" || scheme == "content" || scheme == "android.resource" || scheme == "asset" || scheme == "rawresource" || scheme == "http" || scheme == "https"
    }

    private fun createDataSourceFactory(context: Context): DataSource.Factory =
        ResolvingDataSource.Factory(
            DefaultDataSource.Factory(
                context,
                OkHttpDataSource.Factory(httpClient),
            ),
        ) { dataSpec ->
            // Arquivos locais e URIs reais passam direto pelo ExoPlayer. Só o
            // "uri" sem scheme do YouTube Music é resolvido via Innertube.
            if (isDirectLocalOrHttp(dataSpec.uri)) {
                return@Factory dataSpec
            }

            val mediaId = dataSpec.key?.takeIf { it.isNotBlank() }
                ?: dataSpec.uri.toString().takeIf { it.isNotBlank() }
                ?: error("No media id")

            songUrlCache[mediaId]?.takeIf { it.second > System.currentTimeMillis() }?.let { cached ->
                return@Factory dataSpec.withUri(Uri.parse(cached.first))
            }

            Timber.tag(TAG).i("FETCHING STREAM: %s | quality=%s", mediaId, currentQuality)
            val playbackData = runBlocking(Dispatchers.IO) {
                runCatching {
                    MetrolistStreamResolver.resolvePlaybackForProxy(
                        context.applicationContext,
                        mediaId,
                        currentQuality.name,
                    )
                }
            }.getOrElse { throwable ->
                when (throwable) {
                    is PlaybackException -> throw throwable
                    is ConnectException, is UnknownHostException -> throw PlaybackException(
                        "Sem internet para tocar a música online",
                        throwable,
                        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                    )
                    is SocketTimeoutException -> throw PlaybackException(
                        "Tempo esgotado ao carregar a música online",
                        throwable,
                        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
                    )
                    else -> throw PlaybackException(
                        throwable.message ?: "Erro ao resolver stream pelo Metrolist",
                        throwable,
                        PlaybackException.ERROR_CODE_REMOTE_ERROR,
                    )
                }
            }

            val streamUrl = playbackData.url
            songUrlCache[mediaId] = streamUrl to (
                System.currentTimeMillis() + (playbackData.expiresInSeconds * 1000L) - CACHE_SAFETY_MS
            )
            dataSpec.withUri(Uri.parse(streamUrl)).subrange(dataSpec.uriPositionOffset, CHUNK_LENGTH)
        }

    private fun readBool(value: Any?): Boolean = value == true || value?.toString()?.equals("true", true) == true

    private fun readLong(value: Any?, default: Long = 0L): Long = when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull() ?: default
        else -> default
    }

    private fun mediaItemFromMap(raw: Map<String, Any?>): MediaItem {
        val isRemote = readBool(raw["isRemote"])
        val videoId = (raw["videoId"] as? String).orEmpty().trim()
        val libraryKey = (raw["libraryKey"] as? String).orEmpty().trim().ifBlank {
            if (isRemote && videoId.isNotEmpty()) "remote:${videoId.lowercase(Locale.US)}" else (raw["id"] as? String).orEmpty().trim()
        }
        val title = (raw["title"] as? String).orEmpty().ifBlank { "Música" }
        val artist = (raw["artist"] as? String).orEmpty()
        val album = (raw["album"] as? String).orEmpty()
        val artworkUrl = (raw["artworkUrl"] as? String).orEmpty().trim()
        val durationMs = readLong(raw["durationMs"])

        val uriString = if (isRemote) {
            videoId
        } else {
            (raw["playUri"] as? String).orEmpty().trim().ifBlank {
                (raw["uri"] as? String).orEmpty().trim().ifBlank {
                    val path = (raw["path"] as? String).orEmpty().trim()
                    if (path.isNotEmpty()) Uri.fromFile(File(path)).toString() else ""
                }
            }
        }
        require(uriString.isNotBlank()) { if (isRemote) "videoId vazio" else "arquivo local sem uri" }

        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setDisplayTitle(title)
            .setSubtitle(artist)
            .setArtist(artist)
            .setAlbumTitle(album)
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
            .setIsBrowsable(false)
            .setIsPlayable(true)
        if (artworkUrl.isNotBlank()) {
            runCatching { metadataBuilder.setArtworkUri(Uri.parse(artworkUrl)) }
        }

        val builder = MediaItem.Builder()
            .setMediaId(libraryKey.ifBlank { uriString })
            .setUri(uriString)
            .setMediaMetadata(metadataBuilder.build())
        if (isRemote && videoId.isNotBlank()) {
            builder.setCustomCacheKey(videoId)
        }
        return builder.build()
    }

    @Suppress("UNCHECKED_CAST")
    fun play(context: Context, args: Map<String, Any?>): Map<String, Any?> = onMainSync {
        currentQuality = runCatching {
            AudioQuality.valueOf(((args["quality"] as? String) ?: AudioQuality.AUTO.name).uppercase(Locale.US))
        }.getOrDefault(AudioQuality.AUTO)

        val rawQueue = args["queue"] as? List<Map<String, Any?>>
        val single = mapOf(
            "id" to (args["id"] ?: args["videoId"]),
            "libraryKey" to (args["libraryKey"] ?: args["videoId"]),
            "videoId" to args["videoId"],
            "isRemote" to (args["isRemote"] ?: true),
            "title" to args["title"],
            "artist" to args["artist"],
            "album" to args["album"],
            "artworkUrl" to args["artworkUrl"],
            "durationMs" to args["durationMs"],
            "uri" to args["uri"],
            "playUri" to args["playUri"],
            "path" to args["path"],
        )
        val queueItems = (rawQueue?.takeIf { it.isNotEmpty() } ?: listOf(single)).map { mediaItemFromMap(it) }
        val requestedIndex = readLong(args["index"], 0L).toInt().coerceIn(0, queueItems.lastIndex)

        val nativePlayer = ensurePlayer(context)
        lastError = null
        currentArtworkBitmap = null
        currentArtworkKey = null
        nativePlayer.stop()
        nativePlayer.clearMediaItems()
        nativePlayer.setMediaItems(queueItems, requestedIndex, C.TIME_UNSET)
        nativePlayer.shuffleModeEnabled = readBool(args["shuffle"])
        nativePlayer.repeatMode = when ((args["repeatMode"] as? String).orEmpty()) {
            "track" -> Player.REPEAT_MODE_ONE
            "album" -> Player.REPEAT_MODE_ALL
            else -> Player.REPEAT_MODE_OFF
        }
        nativePlayer.prepare()
        nativePlayer.playWhenReady = true
        nativePlayer.play()
        attachEqualizerToPlayerSession(nativePlayer)
        updateNotification(context.applicationContext)
        state()
    }

    fun pause(): Map<String, Any?> = onMainSync {
        player?.pause()
        appContext?.let { updateNotification(it) }
        state()
    }

    fun resume(): Map<String, Any?> = onMainSync {
        player?.let { resumePrepared(it) }
        appContext?.let { updateNotification(it) }
        state()
    }

    fun seek(positionMs: Long): Map<String, Any?> = onMainSync {
        player?.seekTo(positionMs.coerceAtLeast(0L))
        state()
    }

    fun stop(): Map<String, Any?> = onMainSync {
        player?.stop()
        player?.clearMediaItems()
        currentArtworkBitmap = null
        currentArtworkKey = null
        appContext?.let {
            requestStopForegroundService(it)
            NotificationManagerCompat.from(it).cancel(NOTIFICATION_ID)
        }
        state()
    }

    fun release(): Map<String, Any?> = onMainSync {
        player?.release()
        player = null
        mediaSession?.release()
        mediaSession = null
        songUrlCache.clear()
        playbackErrorRetries.clear()
        appContext?.let { requestStopForegroundService(it) }
        state()
    }

    fun invalidate(videoId: String): Map<String, Any?> = onMainSync {
        val key = videoId.trim()
        if (key.isNotEmpty()) {
            songUrlCache.remove(key)
            MetrolistStreamResolver.invalidate(key)
        }
        state()
    }

    fun updateOptions(args: Map<String, Any?>): Map<String, Any?> = onMainSync {
        val p = player
        if (args.containsKey("shuffle")) p?.shuffleModeEnabled = readBool(args["shuffle"])
        if (args.containsKey("repeatMode")) {
            p?.repeatMode = when ((args["repeatMode"] as? String).orEmpty()) {
                "track" -> Player.REPEAT_MODE_ONE
                "album" -> Player.REPEAT_MODE_ALL
                else -> Player.REPEAT_MODE_OFF
            }
        }
        appContext?.let { updateNotification(it) }
        state()
    }

    fun skipToNext(): Map<String, Any?> = onMainSync {
        val p = player
        if (p != null) {
            when {
                p.nextMediaItemIndex != C.INDEX_UNSET -> p.seekToDefaultPosition(p.nextMediaItemIndex)
                p.repeatMode == Player.REPEAT_MODE_ALL && p.mediaItemCount > 0 -> p.seekToDefaultPosition(0)
                p.mediaItemCount > 0 -> p.seekTo(0, 0L)
            }
            resumePrepared(p)
        }
        appContext?.let { updateNotification(it) }
        state()
    }

    fun skipToPrevious(): Map<String, Any?> = onMainSync {
        val p = player
        if (p != null) {
            if (p.currentPosition > 3000L) {
                p.seekTo(0L)
            } else if (p.previousMediaItemIndex != C.INDEX_UNSET) {
                p.seekToDefaultPosition(p.previousMediaItemIndex)
            } else {
                p.seekTo(0L)
            }
            resumePrepared(p)
        }
        appContext?.let { updateNotification(it) }
        state()
    }

    fun handleNotificationAction(context: Context, action: String) {
        ensureInitialized(context)
        when (action) {
            ACTION_PLAY_PAUSE -> onMainSync { if (player?.isPlaying == true) pause() else resume() }
            ACTION_NEXT -> skipToNext()
            ACTION_PREVIOUS -> skipToPrevious()
            ACTION_SHUFFLE -> onMainSync {
                player?.let { it.shuffleModeEnabled = !it.shuffleModeEnabled }
                updateNotification(context.applicationContext)
            }
            ACTION_REPEAT -> onMainSync {
                player?.let {
                    it.repeatMode = when (it.repeatMode) {
                        Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ONE
                        Player.REPEAT_MODE_ONE -> Player.REPEAT_MODE_ALL
                        else -> Player.REPEAT_MODE_OFF
                    }
                    if (it.playbackState == Player.STATE_ENDED && it.repeatMode != Player.REPEAT_MODE_OFF) {
                        recoverEndedPlayback(it, context.applicationContext)
                    }
                }
                updateNotification(context.applicationContext)
            }
            ACTION_STOP -> stop()
        }
    }

    fun state(): Map<String, Any?> = onMainSync {
        val p = player
        val duration = p?.duration?.takeIf { it != C.TIME_UNSET && it >= 0L } ?: 0L
        val position = p?.currentPosition?.takeIf { it >= 0L } ?: 0L
        val buffered = p?.bufferedPosition?.takeIf { it >= 0L } ?: 0L
        val playbackState = p?.playbackState ?: Player.STATE_IDLE
        // Polling happens twice a second. Do not re-attach/snapshot the full
        // Equalizer on every clock tick; player callbacks already attach it
        // whenever the session/media state changes.
        val audioSessionId = runCatching { p?.audioSessionId ?: 0 }.getOrDefault(0)
        mapOf(
            "playing" to (p?.isPlaying == true),
            "playWhenReady" to (p?.playWhenReady == true),
            "positionMs" to position,
            "durationMs" to duration,
            "bufferedPositionMs" to buffered,
            "mediaId" to (p?.currentMediaItem?.mediaId ?: ""),
            "queueIndex" to (p?.currentMediaItemIndex ?: -1),
            "queueSize" to (p?.mediaItemCount ?: 0),
            "audioSessionId" to audioSessionId,
            "shuffle" to (p?.shuffleModeEnabled == true),
            "repeatMode" to when (p?.repeatMode ?: Player.REPEAT_MODE_OFF) {
                Player.REPEAT_MODE_ONE -> "track"
                Player.REPEAT_MODE_ALL -> "album"
                else -> "off"
            },
            "state" to when (playbackState) {
                Player.STATE_IDLE -> "idle"
                Player.STATE_BUFFERING -> "buffering"
                Player.STATE_READY -> "ready"
                Player.STATE_ENDED -> "ended"
                else -> "unknown"
            },
            "error" to (lastError ?: ""),
        )
    }

    /**
     * True while playback is expected to continue, including buffering and short
     * READY transitions where ExoPlayer may temporarily report isPlaying=false.
     * Keeping the mediaPlayback FGS alive during those transitions prevents the
     * process priority from dropping while a song is still logically active.
     */
    internal fun shouldKeepForegroundService(): Boolean = onMainSync {
        val p = player ?: return@onMainSync false
        val state = p.playbackState
        val hasPlayableItem = p.currentMediaItem != null && p.mediaItemCount > 0
        val canContinueAfterEnded = state == Player.STATE_ENDED && (
            p.repeatMode != Player.REPEAT_MODE_OFF || p.nextMediaItemIndex != C.INDEX_UNSET
        )
        hasPlayableItem && (
            p.isPlaying ||
                (p.playWhenReady && state != Player.STATE_IDLE && state != Player.STATE_ENDED) ||
                (p.playWhenReady && canContinueAfterEnded)
        )
    }

    internal fun promoteToForeground(service: Service) {
        ensureInitialized(service.applicationContext)
        val notification = buildNotification(service.applicationContext) ?: lastNotification ?: return
        lastNotification = notification
        runCatching {
            service.startForeground(NOTIFICATION_ID, notification)
            foregroundServiceActive = true
        }.onFailure { Timber.tag(TAG).w(it, "Falha ao iniciar foreground service do player") }
    }

    internal fun stopForegroundService(service: Service) {
        runCatching {
            @Suppress("DEPRECATION")
            service.stopForeground(false)
            foregroundServiceActive = false
        }
    }

    private fun requestForegroundService(context: Context) {
        val intent = Intent(context, MetrolistPlaybackService::class.java).setAction(ACTION_SERVICE_START)
        runCatching { ContextCompat.startForegroundService(context, intent) }
            .onFailure { Timber.tag(TAG).w(it, "Falha ao solicitar foreground service") }
    }

    private fun requestStopForegroundService(context: Context) {
        val intent = Intent(context, MetrolistPlaybackService::class.java).setAction(ACTION_SERVICE_STOP_FOREGROUND)
        runCatching { context.startService(intent) }
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Player de música",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Controles de reprodução do Music"
                    setShowBadge(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                },
            )
        }
    }

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MetrolistPlayerActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(context, 99, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun httpArtworkCandidates(raw: String): List<String> {
        val candidates = linkedSetOf<String>()
        val url = raw.trim()
        if (url.isBlank()) return emptyList()
        candidates += url
        if (url.contains("/maxresdefault.jpg")) {
            candidates += url.replace("/maxresdefault.jpg", "/hqdefault.jpg")
            candidates += url.replace("/maxresdefault.jpg", "/sddefault.jpg")
            candidates += url.replace("/maxresdefault.jpg", "/mqdefault.jpg")
        }
        if (Regex("=w\\d+-h\\d+(?:-[^?&]*)?").containsMatchIn(url)) {
            candidates += url.replace(Regex("=w\\d+-h\\d+(?:-[^?&]*)?"), "=w1024-h1024-l90-rj")
            candidates += url.replace(Regex("=w\\d+-h\\d+(?:-[^?&]*)?"), "=w544-h544-l90-rj")
        }
        return candidates.toList()
    }

    private fun decodeArtwork(bytes: ByteArray): Bitmap? {
        if (bytes.isEmpty()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / sample > ARTWORK_MAX_EDGE * 2 || bounds.outHeight / sample > ARTWORK_MAX_EDGE * 2) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return scaleArtwork(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options))
    }

    private fun decodeArtworkFile(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / sample > ARTWORK_MAX_EDGE * 2 || bounds.outHeight / sample > ARTWORK_MAX_EDGE * 2) {
            sample *= 2
        }
        return scaleArtwork(BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }))
    }

    private fun scaleArtwork(bitmap: Bitmap?): Bitmap? {
        bitmap ?: return null
        val largest = maxOf(bitmap.width, bitmap.height)
        if (largest <= ARTWORK_MAX_EDGE) return bitmap
        val scale = ARTWORK_MAX_EDGE.toFloat() / largest.toFloat()
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true).also { scaled ->
            if (scaled !== bitmap) runCatching { bitmap.recycle() }
        }
    }

    private fun downloadArtwork(rawUrl: String): Bitmap? {
        for (url in httpArtworkCandidates(rawUrl)) {
            val bitmap = runCatching {
                val request = Request.Builder()
                    .url(url)
                    .header("User-Agent", ARTWORK_USER_AGENT)
                    .header("Referer", "https://music.youtube.com/")
                    .header("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
                    .build()
                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) null else response.body?.bytes()?.let(::decodeArtwork)
                }
            }.getOrNull()
            if (bitmap != null) return bitmap
        }
        return null
    }

    private fun maybeLoadArtworkAsync(context: Context, uri: Uri?) {
        val key = uri?.toString().orEmpty()
        if (key.isBlank() || key == currentArtworkKey) return
        currentArtworkKey = key
        artExecutor.execute {
            val bitmap = runCatching {
                when (uri?.scheme?.lowercase(Locale.US)) {
                    "http", "https" -> downloadArtwork(key)
                    "file" -> decodeArtworkFile(uri.path)
                    "content" -> context.contentResolver.openInputStream(uri).use { input ->
                        if (input == null) null else decodeArtwork(input.readBytes())
                    }
                    else -> null
                }
            }.getOrNull()
            if (bitmap != null && currentArtworkKey == key) {
                currentArtworkBitmap = bitmap
                mainHandler.post { updateNotification(context) }
            } else if (bitmap != null) {
                runCatching { bitmap.recycle() }
            }
        }
    }

    private fun buildNotification(context: Context): Notification? {
        val p = player ?: return null
        val item = p.currentMediaItem ?: return null
        val meta = item.mediaMetadata
        val title = meta.title?.toString()?.takeIf { it.isNotBlank() } ?: "Music"
        val artist = meta.artist?.toString()?.takeIf { it.isNotBlank() }
            ?: meta.subtitle?.toString()?.takeIf { it.isNotBlank() }
            ?: ""
        val artworkUri = meta.artworkUri
        maybeLoadArtworkAsync(context, artworkUri)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return null
        }

        val playing = p.isPlaying || (p.playWhenReady && p.playbackState == Player.STATE_BUFFERING)
        val repeatTitle = when (p.repeatMode) {
            Player.REPEAT_MODE_ONE -> "Repetir faixa"
            Player.REPEAT_MODE_ALL -> "Repetir fila"
            else -> "Sem repetição"
        }
        val shuffleTitle = if (p.shuffleModeEnabled) "Aleatório ligado" else "Aleatório desligado"
        val repeatModeCompat = when (p.repeatMode) {
            Player.REPEAT_MODE_ONE -> PlaybackStateCompat.REPEAT_MODE_ONE
            Player.REPEAT_MODE_ALL -> PlaybackStateCompat.REPEAT_MODE_ALL
            else -> PlaybackStateCompat.REPEAT_MODE_NONE
        }
        val shuffleModeCompat = if (p.shuffleModeEnabled) {
            PlaybackStateCompat.SHUFFLE_MODE_ALL
        } else {
            PlaybackStateCompat.SHUFFLE_MODE_NONE
        }
        val session = ensureMediaSession(context).apply {
            val duration = p.duration.takeIf { it != C.TIME_UNSET && it >= 0L } ?: 0L
            val metadataBuilder = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, meta.albumTitle?.toString().orEmpty())
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
            artworkUri?.toString()?.takeIf { it.isNotBlank() }?.let { artUri ->
                metadataBuilder
                    .putString(MediaMetadataCompat.METADATA_KEY_ART_URI, artUri)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, artUri)
                    .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, artUri)
            }
            currentArtworkBitmap?.let { artwork ->
                metadataBuilder
                    .putBitmap(MediaMetadataCompat.METADATA_KEY_ART, artwork)
                    .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artwork)
                    .putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artwork)
            }
            setMetadata(metadataBuilder.build())
            setRepeatMode(repeatModeCompat)
            setShuffleMode(shuffleModeCompat)
            val playbackState = when {
                p.playbackState == Player.STATE_BUFFERING -> PlaybackStateCompat.STATE_BUFFERING
                playing -> PlaybackStateCompat.STATE_PLAYING
                p.playbackState == Player.STATE_ENDED -> PlaybackStateCompat.STATE_STOPPED
                else -> PlaybackStateCompat.STATE_PAUSED
            }
            val playbackStateBuilder = PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                            PlaybackStateCompat.ACTION_PAUSE or
                            PlaybackStateCompat.ACTION_PLAY_PAUSE or
                            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                            PlaybackStateCompat.ACTION_SEEK_TO or
                            PlaybackStateCompat.ACTION_SET_REPEAT_MODE or
                            PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE or
                            PlaybackStateCompat.ACTION_STOP,
                    )
                    .setState(playbackState, p.currentPosition.coerceAtLeast(0L), if (playing) 1f else 0f)
                    .addCustomAction(ACTION_SHUFFLE, shuffleTitle, R.drawable.ic_shuffle)
                    .addCustomAction(
                        ACTION_REPEAT,
                        repeatTitle,
                        if (p.repeatMode == Player.REPEAT_MODE_ONE) R.drawable.ic_repeat_one else R.drawable.ic_repeat,
                    )
            setPlaybackState(playbackStateBuilder.build())
        }
        val playPauseAction = if (playing) {
            NotificationCompat.Action(android.R.drawable.ic_media_pause, "Pausar", actionIntent(context, ACTION_PLAY_PAUSE, 1))
        } else {
            NotificationCompat.Action(android.R.drawable.ic_media_play, "Tocar", actionIntent(context, ACTION_PLAY_PAUSE, 1))
        }
        val shuffleAction = NotificationCompat.Action(
            R.drawable.ic_shuffle,
            shuffleTitle,
            actionIntent(context, ACTION_SHUFFLE, 5),
        )
        val repeatAction = NotificationCompat.Action(
            if (p.repeatMode == Player.REPEAT_MODE_ONE) R.drawable.ic_repeat_one else R.drawable.ic_repeat,
            repeatTitle,
            actionIntent(context, ACTION_REPEAT, 4),
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(meta.albumTitle?.toString().orEmpty())
            .setLargeIcon(currentArtworkBitmap)
            .setContentIntent(openAppIntent(context))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setColor(0xFF5B8CFF.toInt())
            .setColorized(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(shuffleAction)
            .addAction(NotificationCompat.Action(android.R.drawable.ic_media_previous, "Anterior", actionIntent(context, ACTION_PREVIOUS, 2)))
            .addAction(playPauseAction)
            .addAction(NotificationCompat.Action(android.R.drawable.ic_media_next, "Próxima", actionIntent(context, ACTION_NEXT, 3)))
            .addAction(repeatAction)
            .setStyle(
                MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(1, 2, 3),
            )
            .build()
    }

    private fun updateNotification(context: Context) {
        val p = player ?: return
        val notification = buildNotification(context) ?: return
        lastNotification = notification
        val keepForeground = shouldKeepForegroundService()
        if (keepForeground) {
            requestForegroundService(context.applicationContext)
        } else if (foregroundServiceActive) {
            requestStopForegroundService(context.applicationContext)
        }
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
    }

}
