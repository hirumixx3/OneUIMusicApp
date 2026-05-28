package com.hirumisu.musicapp

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
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
import androidx.media3.extractor.mp4.FragmentedMp4Extractor
import androidx.media3.extractor.mkv.MatroskaExtractor
import com.metrolist.music.constants.AudioQuality
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference
import timber.log.Timber

/**
 * Native online player that follows Metrolist's Android playback path.
 *
 * Online tracks do not go through Flutter/just_audio and do not receive a
 * pre-resolved localhost/googlevideo URL.  ExoPlayer opens a media item whose
 * URI/key is the YouTube video id, then ResolvingDataSource resolves each
 * requested chunk through Metrolist's YTPlayerUtils.playerResponseForPlayback,
 * exactly like the old Metrolist MusicService flow.
 */
object MetrolistNativePlayer {
    private const val TAG = "MetrolistNativePlayer"
    private const val CHUNK_LENGTH = 512 * 1024L

    @Volatile private var appContext: Context? = null
    @Volatile private var player: ExoPlayer? = null
    @Volatile private var lastError: String? = null
    @Volatile private var currentQuality: String = AudioQuality.AUTO.name

    private val mainHandler = Handler(Looper.getMainLooper())
    private val songUrlCache = ConcurrentHashMap<String, Pair<String, Long>>()

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

    private fun ensurePlayer(context: Context): ExoPlayer {
        check(Looper.myLooper() == Looper.getMainLooper()) { "MetrolistNativePlayer precisa rodar na main thread" }
        appContext = context.applicationContext
        player?.let { return it }
        synchronized(this) {
            player?.let { return it }
            if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
            val created = ExoPlayer.Builder(context.applicationContext)
                .setLooper(Looper.getMainLooper())
                .setMediaSourceFactory(createMediaSourceFactory(context.applicationContext))
                .build()
            created.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    val mediaId = created.currentMediaItem?.mediaId
                    lastError = "${error.errorCodeName}: ${error.message ?: error.cause?.message ?: "erro"}"
                    if (!mediaId.isNullOrBlank()) {
                        songUrlCache.remove(mediaId)
                        MetrolistStreamResolver.invalidate(mediaId)
                    }
                    Timber.tag(TAG).w(error, "Native player error for %s", mediaId)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_READY) {
                        lastError = null
                    }
                }
            })
            player = created
            return created
        }
    }

    private fun createMediaSourceFactory(context: Context): DefaultMediaSourceFactory =
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
                OkHttpDataSource.Factory(MetrolistStreamResolver.httpClient)
                    .setUserAgent(MetrolistStreamResolver.UPSTREAM_USER_AGENT)
                    .setDefaultRequestProperties(
                        mapOf(
                            "Accept" to "*/*",
                            "Accept-Encoding" to "identity",
                            "Referer" to "https://music.youtube.com/",
                        ),
                    ),
            ),
        ) { dataSpec ->
            val mediaId = dataSpec.key?.takeIf { it.isNotBlank() }
                ?: dataSpec.uri.toString().takeIf { it.isNotBlank() }
                ?: error("No media id")

            val now = System.currentTimeMillis()
            songUrlCache[mediaId]?.takeIf { it.second > now }?.let { cached ->
                // Same behavior as the old Metrolist MusicService: once the stream URL is cached,
                // keep ExoPlayer's requested range untouched and only replace the URI.
                return@Factory dataSpec.withUri(Uri.parse(cached.first))
            }

            val playback = MetrolistStreamResolver.resolvePlaybackForProxy(
                context = context.applicationContext,
                videoId = mediaId,
                qualityName = currentQuality,
                forceRefresh = false,
            )
            songUrlCache[mediaId] = playback.url to (System.currentTimeMillis() + playback.streamTtlMs())
            dataSpec.withUri(Uri.parse(playback.url)).subrange(dataSpec.uriPositionOffset, CHUNK_LENGTH)
        }

    private fun MetrolistStreamResolver.NativePlayback.streamTtlMs(): Long =
        kotlin.math.max(60_000L, expiresInSeconds.coerceAtLeast(60) * 1000L - 120_000L)

    fun play(context: Context, args: Map<String, Any?>): Map<String, Any?> = onMainSync {
        val videoId = (args["videoId"] as? String).orEmpty().trim()
        require(videoId.isNotEmpty()) { "videoId vazio" }
        currentQuality = ((args["quality"] as? String) ?: AudioQuality.AUTO.name).uppercase(Locale.US)
            .ifBlank { AudioQuality.AUTO.name }
        val title = (args["title"] as? String).orEmpty().ifBlank { "Música online" }
        val artist = (args["artist"] as? String).orEmpty()
        val album = (args["album"] as? String).orEmpty()
        val artworkUrl = (args["artworkUrl"] as? String).orEmpty().trim()
        val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 0L

        val nativePlayer = ensurePlayer(context)
        lastError = null

        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setDisplayTitle(title)
            .setSubtitle(artist)
            .setArtist(artist)
            .setAlbumTitle(album)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
        if (artworkUrl.startsWith("http://") || artworkUrl.startsWith("https://")) {
            metadataBuilder.setArtworkUri(Uri.parse(artworkUrl))
        }

        val itemBuilder = MediaItem.Builder()
            .setMediaId(videoId)
            .setUri(videoId)
            .setCustomCacheKey(videoId)
            .setMediaMetadata(metadataBuilder.build())
        // Duration is reported back to Flutter from its catalog metadata; the
        // media item itself must stay unclipped like Metrolist.
        @Suppress("UNUSED_VARIABLE")
        val ignoredDurationMs = durationMs

        nativePlayer.setMediaItem(itemBuilder.build())
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
        if (key.isNotEmpty()) {
            songUrlCache.remove(key)
            MetrolistStreamResolver.invalidate(key)
        }
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
