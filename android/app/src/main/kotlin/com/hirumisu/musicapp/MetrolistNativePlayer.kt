package com.hirumisu.musicapp

import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
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
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.mkv.MatroskaExtractor
import androidx.media3.extractor.mp4.FragmentedMp4Extractor
import com.metrolist.innertube.YouTube
import com.metrolist.music.constants.AudioQuality
import com.metrolist.music.utils.YTPlayerUtils
import com.metrolist.music.utils.cipher.CipherDeobfuscator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import timber.log.Timber
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

/**
 * Player online nativo, sem just_audio.
 *
 * Este arquivo replica o caminho de reprodução do Metrolist antigo:
 * ExoPlayer -> ResolvingDataSource -> YTPlayerUtils.playerResponseForPlayback -> googlevideo por ranges.
 * O Flutter só manda o videoId e controla play/pause/seek.
 */
object MetrolistNativePlayer {
    private const val TAG = "MetrolistNativePlayer"
    private const val CHUNK_LENGTH = 512 * 1024L
    private const val CACHE_SAFETY_MS = 120_000L

    @Volatile private var appContext: Context? = null
    @Volatile private var player: ExoPlayer? = null
    @Volatile private var lastError: String? = null
    @Volatile private var currentQuality: AudioQuality = AudioQuality.AUTO

    private val mainHandler = Handler(Looper.getMainLooper())
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
        MetrolistYouTubeSession.restore(app, blockForVisitor = false)
        runCatching { CipherDeobfuscator.initialize(app) }
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
                lastError = "${error.errorCodeName}: ${error.message ?: error.cause?.message ?: "erro"}"
                if (mediaId.isNotBlank()) songUrlCache.remove(mediaId)
                Timber.tag(TAG).e(error, "Erro no player nativo do Metrolist para %s", mediaId)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                Timber.tag(TAG).d("state=%s playing=%s playWhenReady=%s pos=%s mediaId=%s",
                    playbackState,
                    created.isPlaying,
                    created.playWhenReady,
                    created.currentPosition,
                    created.currentMediaItem?.mediaId,
                )
                if (playbackState == Player.STATE_READY) lastError = null
            }
        })
        player = created
        return created
    }

    private fun createMediaSourceFactory(context: Context) =
        DefaultMediaSourceFactory(
            createDataSourceFactory(context),
            ExtractorsFactory {
                arrayOf<Extractor>(MatroskaExtractor(), FragmentedMp4Extractor())
            },
        )

    private fun createDataSourceFactory(context: Context): DataSource.Factory =
        ResolvingDataSource.Factory(
            DefaultDataSource.Factory(
                context,
                OkHttpDataSource.Factory(httpClient),
            ),
        ) { dataSpec ->
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

    fun play(context: Context, args: Map<String, Any?>): Map<String, Any?> = onMainSync {
        val videoId = (args["videoId"] as? String).orEmpty().trim()
        require(videoId.isNotEmpty()) { "videoId vazio" }
        currentQuality = runCatching {
            AudioQuality.valueOf(((args["quality"] as? String) ?: AudioQuality.AUTO.name).uppercase(Locale.US))
        }.getOrDefault(AudioQuality.AUTO)

        val title = (args["title"] as? String).orEmpty().ifBlank { "Música online" }
        val artist = (args["artist"] as? String).orEmpty()
        val album = (args["album"] as? String).orEmpty()
        val artworkUrl = (args["artworkUrl"] as? String).orEmpty().trim()

        val nativePlayer = ensurePlayer(context)
        lastError = null

        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setDisplayTitle(title)
            .setSubtitle(artist)
            .setArtist(artist)
            .setAlbumTitle(album)
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
            .setIsBrowsable(false)
            .setIsPlayable(true)
        if (artworkUrl.startsWith("http://") || artworkUrl.startsWith("https://")) {
            metadataBuilder.setArtworkUri(Uri.parse(artworkUrl))
        }

        val mediaItem = MediaItem.Builder()
            .setMediaId(videoId)
            .setUri(videoId)
            .setCustomCacheKey(videoId)
            .setMediaMetadata(metadataBuilder.build())
            .build()

        // Faz igual ao Metrolist: o item é o videoId, e o ResolvingDataSource resolve quando o ExoPlayer abrir bytes.
        nativePlayer.stop()
        nativePlayer.clearMediaItems()
        nativePlayer.setMediaItem(mediaItem)
        nativePlayer.prepare()
        nativePlayer.playWhenReady = true
        nativePlayer.play()
        state()
    }

    fun pause(): Map<String, Any?> = onMainSync {
        player?.pause()
        state()
    }

    fun resume(): Map<String, Any?> = onMainSync {
        player?.playWhenReady = true
        player?.play()
        state()
    }

    fun seek(positionMs: Long): Map<String, Any?> = onMainSync {
        player?.seekTo(positionMs.coerceAtLeast(0L))
        state()
    }

    fun stop(): Map<String, Any?> = onMainSync {
        player?.stop()
        player?.clearMediaItems()
        state()
    }

    fun release(): Map<String, Any?> = onMainSync {
        player?.release()
        player = null
        songUrlCache.clear()
        state()
    }

    fun invalidate(videoId: String): Map<String, Any?> = onMainSync {
        val key = videoId.trim()
        if (key.isNotEmpty()) songUrlCache.remove(key)
        state()
    }

    fun state(): Map<String, Any?> = onMainSync {
        val p = player
        val duration = p?.duration?.takeIf { it != C.TIME_UNSET && it >= 0L } ?: 0L
        val position = p?.currentPosition?.takeIf { it >= 0L } ?: 0L
        val buffered = p?.bufferedPosition?.takeIf { it >= 0L } ?: 0L
        val playbackState = p?.playbackState ?: Player.STATE_IDLE
        mapOf(
            "playing" to (p?.isPlaying == true),
            "playWhenReady" to (p?.playWhenReady == true),
            "positionMs" to position,
            "durationMs" to duration,
            "bufferedPositionMs" to buffered,
            "mediaId" to (p?.currentMediaItem?.mediaId ?: ""),
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
}
