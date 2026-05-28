package com.hirumisu.musicapp

import android.Manifest
import android.app.NotificationChannel
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
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
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
import com.metrolist.music.utils.YTPlayerUtils
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
 * Online: ExoPlayer -> ResolvingDataSource -> YTPlayerUtils/Innertube.
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

    const val ACTION_PLAY_PAUSE = "com.hirumisu.musicapp.action.PLAY_PAUSE"
    const val ACTION_NEXT = "com.hirumisu.musicapp.action.NEXT"
    const val ACTION_PREVIOUS = "com.hirumisu.musicapp.action.PREVIOUS"
    const val ACTION_SHUFFLE = "com.hirumisu.musicapp.action.SHUFFLE"
    const val ACTION_REPEAT = "com.hirumisu.musicapp.action.REPEAT"
    const val ACTION_STOP = "com.hirumisu.musicapp.action.STOP"

    @Volatile private var appContext: Context? = null
    @Volatile private var player: ExoPlayer? = null
    @Volatile private var lastError: String? = null
    @Volatile private var currentQuality: AudioQuality = AudioQuality.AUTO
    @Volatile private var currentArtworkBitmap: Bitmap? = null
    @Volatile private var currentArtworkKey: String? = null
    @Volatile private var mediaSession: MediaSessionCompat? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val artExecutor = Executors.newSingleThreadExecutor()
    private val songUrlCache = ConcurrentHashMap<String, Pair<String, Long>>()

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

    private fun recoverEndedPlayback(p: ExoPlayer, context: Context) {
        if (!p.playWhenReady || p.mediaItemCount <= 0) return
        mainHandler.post {
            val current = player ?: return@post
            if (current !== p || current.playbackState != Player.STATE_ENDED || !current.playWhenReady) return@post
            when {
                current.repeatMode == Player.REPEAT_MODE_ONE -> {
                    val index = current.currentMediaItemIndex.coerceAtLeast(0)
                    current.seekTo(index, 0L)
                    resumePrepared(current)
                }
                current.nextMediaItemIndex != C.INDEX_UNSET -> {
                    current.seekToNextMediaItem()
                    resumePrepared(current)
                }
                current.repeatMode == Player.REPEAT_MODE_ALL && current.mediaItemCount > 0 -> {
                    current.seekTo(0, 0L)
                    resumePrepared(current)
                }
            }
            updateNotification(context.applicationContext)
        }
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
                if (mediaId.isNotBlank()) songUrlCache.remove(mediaId)
                Timber.tag(TAG).e(error, "Erro no player nativo do Metrolist para %s", mediaId)
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
                if (playbackState == Player.STATE_READY) lastError = null
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
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val playbackData = runBlocking(Dispatchers.IO) {
                YTPlayerUtils.playerResponseForPlayback(
                    mediaId,
                    audioQuality = currentQuality,
                    connectivityManager = connectivityManager,
                )
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

            val streamUrl = playbackData.streamUrl
            songUrlCache[mediaId] = streamUrl to (
                System.currentTimeMillis() + (playbackData.streamExpiresInSeconds * 1000L) - CACHE_SAFETY_MS
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
        appContext?.let { NotificationManagerCompat.from(it).cancel(NOTIFICATION_ID) }
        state()
    }

    fun release(): Map<String, Any?> = onMainSync {
        player?.release()
        player = null
        mediaSession?.release()
        mediaSession = null
        songUrlCache.clear()
        state()
    }

    fun invalidate(videoId: String): Map<String, Any?> = onMainSync {
        val key = videoId.trim()
        if (key.isNotEmpty()) songUrlCache.remove(key)
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
                p.nextMediaItemIndex != C.INDEX_UNSET -> p.seekToNextMediaItem()
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
                p.seekToPreviousMediaItem()
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
        val audioSessionId = attachEqualizerToPlayerSession(p)
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
            "equalizer" to AppEqualizer.getState(),
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

    private fun maybeLoadArtworkAsync(context: Context, uri: Uri?) {
        val key = uri?.toString().orEmpty()
        if (key.isBlank() || key == currentArtworkKey) return
        currentArtworkKey = key
        artExecutor.execute {
            val bitmap = runCatching {
                when (uri?.scheme?.lowercase(Locale.US)) {
                    "http", "https" -> {
                        val request = Request.Builder().url(key).header("User-Agent", "Metrolist/Flutter Music App").build()
                        httpClient.newCall(request).execute().use { response ->
                            if (!response.isSuccessful) null else response.body?.byteStream()?.use { stream -> BitmapFactory.decodeStream(stream) }
                        }
                    }
                    "file" -> BitmapFactory.decodeFile(uri.path)
                    "content" -> context.contentResolver.openInputStream(uri).use { input ->
                        if (input == null) null else BitmapFactory.decodeStream(input)
                    }
                    else -> null
                }
            }.getOrNull()
            if (bitmap != null) {
                currentArtworkBitmap = bitmap
                mainHandler.post { updateNotification(context) }
            }
        }
    }

    private fun updateNotification(context: Context) {
        val p = player ?: return
        val item = p.currentMediaItem ?: return
        val meta = item.mediaMetadata
        val title = meta.title?.toString()?.takeIf { it.isNotBlank() } ?: "Music"
        val artist = meta.artist?.toString()?.takeIf { it.isNotBlank() }
            ?: meta.subtitle?.toString()?.takeIf { it.isNotBlank() }
            ?: ""
        val artworkUri = meta.artworkUri
        maybeLoadArtworkAsync(context, artworkUri)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        val playing = p.isPlaying || (p.playWhenReady && p.playbackState == Player.STATE_BUFFERING)
        val session = ensureMediaSession(context).apply {
            val duration = p.duration.takeIf { it != C.TIME_UNSET && it >= 0L } ?: 0L
            val metadata = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, meta.albumTitle?.toString().orEmpty())
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                .apply { currentArtworkBitmap?.let { putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) } }
                .build()
            setMetadata(metadata)
            val playbackState = when {
                p.playbackState == Player.STATE_BUFFERING -> PlaybackStateCompat.STATE_BUFFERING
                playing -> PlaybackStateCompat.STATE_PLAYING
                p.playbackState == Player.STATE_ENDED -> PlaybackStateCompat.STATE_STOPPED
                else -> PlaybackStateCompat.STATE_PAUSED
            }
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                            PlaybackStateCompat.ACTION_PAUSE or
                            PlaybackStateCompat.ACTION_PLAY_PAUSE or
                            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                            PlaybackStateCompat.ACTION_SEEK_TO or
                            PlaybackStateCompat.ACTION_STOP,
                    )
                    .setState(playbackState, p.currentPosition.coerceAtLeast(0L), if (playing) 1f else 0f)
                    .build(),
            )
        }
        val playPauseAction = if (playing) {
            NotificationCompat.Action(android.R.drawable.ic_media_pause, "Pausar", actionIntent(context, ACTION_PLAY_PAUSE, 1))
        } else {
            NotificationCompat.Action(android.R.drawable.ic_media_play, "Tocar", actionIntent(context, ACTION_PLAY_PAUSE, 1))
        }
        val repeatTitle = when (p.repeatMode) {
            Player.REPEAT_MODE_ONE -> "Repetir faixa"
            Player.REPEAT_MODE_ALL -> "Repetir fila"
            else -> "Sem repetição"
        }
        val shuffleTitle = if (p.shuffleModeEnabled) "Aleatório ligado" else "Aleatório desligado"

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
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
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(NotificationCompat.Action(android.R.drawable.ic_media_previous, "Anterior", actionIntent(context, ACTION_PREVIOUS, 2)))
            .addAction(playPauseAction)
            .addAction(NotificationCompat.Action(android.R.drawable.ic_media_next, "Próxima", actionIntent(context, ACTION_NEXT, 3)))
            .addAction(NotificationCompat.Action(android.R.drawable.ic_menu_revert, repeatTitle, actionIntent(context, ACTION_REPEAT, 4)))
            .addAction(NotificationCompat.Action(android.R.drawable.ic_menu_sort_by_size, shuffleTitle, actionIntent(context, ACTION_SHUFFLE, 5)))
            .setStyle(
                MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
    }
}
