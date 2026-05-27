package com.hirumisu.musicapp

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.mp4.FragmentedMp4Extractor
import androidx.media3.extractor.mkv.MatroskaExtractor
import com.metrolist.music.constants.AudioQuality
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
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

    private val songUrlCache = ConcurrentHashMap<String, Pair<String, Long>>()

    private fun ensurePlayer(context: Context): ExoPlayer {
        appContext = context.applicationContext
        player?.let { return it }
        synchronized(this) {
            player?.let { return it }
            if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
            val created = ExoPlayer.Builder(context.applicationContext)
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
        ResolvingDataSource.Factory(DefaultDataSource.Factory(context)) { dataSpec ->
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

    fun play(context: Context, args: Map<String, Any?>): Map<String, Any?> {
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
        return state()
    }

    fun pause(): Map<String, Any?> {
        player?.pause()
        return state()
    }

    fun resume(): Map<String, Any?> {
        player?.playWhenReady = true
        player?.play()
        return state()
    }

    fun seek(positionMs: Long): Map<String, Any?> {
        player?.seekTo(positionMs.coerceAtLeast(0L))
        return state()
    }

    fun stop(): Map<String, Any?> {
        player?.stop()
        player?.clearMediaItems()
        return state()
    }

    fun release(): Map<String, Any?> {
        player?.release()
        player = null
        songUrlCache.clear()
        return state()
    }

    fun invalidate(videoId: String): Map<String, Any?> {
        val key = videoId.trim()
        if (key.isNotEmpty()) {
            songUrlCache.remove(key)
            MetrolistStreamResolver.invalidate(key)
        }
        return state()
    }

    fun state(): Map<String, Any?> {
        val p = player
        val duration = p?.duration?.takeIf { it != C.TIME_UNSET && it >= 0L } ?: 0L
        val position = p?.currentPosition?.takeIf { it >= 0L } ?: 0L
        val buffered = p?.bufferedPosition?.takeIf { it >= 0L } ?: 0L
        val playbackState = p?.playbackState ?: Player.STATE_IDLE
        return mapOf(
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
