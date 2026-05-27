package com.hirumisu.musicapp

import android.content.Context
import android.net.ConnectivityManager
import com.metrolist.innertube.NewPipeExtractor
import com.metrolist.innertube.NewPipeUtils
import com.metrolist.innertube.YouTube
import com.metrolist.innertube.models.YouTubeClient
import com.metrolist.innertube.models.response.PlayerResponse
import com.metrolist.music.constants.AudioQuality
import com.metrolist.music.utils.YTPlayerUtils
import com.metrolist.music.utils.cipher.CipherDeobfuscator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request
import timber.log.Timber
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min

/**
 * Android-native YouTube Music playback bridge.
 *
 * The old Flutter build was giving ExoPlayer a raw googlevideo URL. On Samsung
 * Android 16 those URLs repeatedly returned HTTP 403 to ExoPlayer, so playback
 * stayed at 00:00. Metrolist does not play those URLs this way: it uses a native
 * ResolvingDataSource and only opens small byte ranges. This bridge recreates
 * that behavior for just_audio by returning a localhost URL backed by native
 * Innertube/YTPlayerUtils and chunked googlevideo byte requests.
 *
 * Dart remains UI-only. Online stream resolving is fully native/Metrolist.
 */
object MetrolistStreamResolver {
    private const val TAG = "MetrolistStreamResolver"
    private const val CACHE_SAFETY_MS = 120_000L

    @Volatile private var initialized = false

    internal data class NativePlayback(
        val url: String,
        val mimeType: String,
        val bitrate: Int,
        val itag: Int,
        val expiresInSeconds: Int,
        val contentLength: Long?,
        val durationMs: Long,
        val title: String,
        val source: String,
    )

    private data class CachedPlayback(
        val data: NativePlayback,
        val expiresAtMs: Long,
    )

    private val playbackCache = ConcurrentHashMap<String, CachedPlayback>()
    private val resolveLocks = ConcurrentHashMap<String, Any>()

    internal val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .proxy(YouTube.proxy)
            .proxyAuthenticator { _, response ->
                YouTube.proxyAuth?.let { auth ->
                    response.request.newBuilder()
                        .header("Proxy-Authorization", auth)
                        .build()
                } ?: response.request
            }
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(45, TimeUnit.SECONDS)
            .build()
    }

    private fun ensureInitialized(context: Context) {
        if (!initialized) {
            synchronized(this) {
                if (!initialized) {
                    if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
                    CipherDeobfuscator.initialize(context.applicationContext)
                    NewPipeUtils.ensureInitialized()
                    initialized = true
                }
            }
        }
    }

    fun resolve(
        context: Context,
        videoId: String,
        qualityName: String = "AUTO",
        forceRefresh: Boolean = false,
    ): Map<String, Any?> {
        val safeVideoId = videoId.trim()
        require(safeVideoId.isNotEmpty()) { "videoId vazio" }
        ensureInitialized(context)

        val quality = runCatching { AudioQuality.valueOf(qualityName.uppercase(Locale.US)) }
            .getOrDefault(AudioQuality.AUTO)
        if (forceRefresh) invalidate(safeVideoId)

        // Return immediately. The native local stream opens the real googlevideo
        // URL only when ExoPlayer requests bytes, matching Metrolist's
        // ResolvingDataSource flow and avoiding Flutter-side stream services.
        val localUrl = MetrolistNativeStreamServer.urlFor(
            context.applicationContext,
            safeVideoId,
            quality.name,
        )

        return mapOf(
            "url" to localUrl,
            "mimeType" to "audio/webm",
            "bitrate" to 0,
            "itag" to 0,
            "expiresInSeconds" to 1800,
            "durationMs" to 0L,
            "title" to "",
            "source" to "metrolist_native_chunked_resolver",
        )
    }


    fun prewarm(
        context: Context,
        videoId: String,
        qualityName: String = "AUTO",
    ): Map<String, Any?> {
        val safeVideoId = videoId.trim()
        require(safeVideoId.isNotEmpty()) { "videoId vazio" }
        ensureInitialized(context)
        val playback = resolvePlaybackForProxy(context.applicationContext, safeVideoId, qualityName, forceRefresh = false)
        return mapOf(
            "ready" to true,
            "mimeType" to playback.mimeType,
            "bitrate" to playback.bitrate,
            "itag" to playback.itag,
            "source" to playback.source,
        )
    }

    internal fun invalidate(videoId: String) {
        val normalized = videoId.trim()
        playbackCache.remove(normalized)
        playbackCache.keys
            .filter { it == normalized || it.startsWith("$normalized:") }
            .forEach { playbackCache.remove(it) }
    }

    internal fun resolvePlaybackForProxy(
        context: Context,
        videoId: String,
        qualityName: String,
        forceRefresh: Boolean = false,
    ): NativePlayback {
        val safeVideoId = videoId.trim()
        ensureInitialized(context)
        val quality = runCatching { AudioQuality.valueOf(qualityName.uppercase(Locale.US)) }
            .getOrDefault(AudioQuality.AUTO)
        val cacheKey = "$safeVideoId:${quality.name}"
        val now = System.currentTimeMillis()
        if (!forceRefresh) {
            playbackCache[cacheKey]?.takeIf { it.expiresAtMs > now }?.let { return it.data }
        }

        val lock = resolveLocks.getOrPut(cacheKey) { Any() }
        synchronized(lock) {
            val lockedNow = System.currentTimeMillis()
            if (!forceRefresh) {
                playbackCache[cacheKey]?.takeIf { it.expiresAtMs > lockedNow }?.let { return it.data }
            }

            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val data = runBlocking(Dispatchers.IO) {
                resolveNativePlaybackData(safeVideoId, quality, connectivityManager)
            }
            val ttlMs = max(60_000L, data.expiresInSeconds * 1000L - CACHE_SAFETY_MS)
            playbackCache[cacheKey] = CachedPlayback(data, System.currentTimeMillis() + ttlMs)
            return data
        }
    }

    private suspend fun resolveNativePlaybackData(
        videoId: String,
        quality: AudioQuality,
        connectivityManager: ConnectivityManager,
    ): NativePlayback {
        val metrolistResult = YTPlayerUtils.playerResponseForPlayback(
            videoId = videoId,
            playlistId = null,
            audioQuality = quality,
            connectivityManager = connectivityManager,
        )
        val metrolistData = metrolistResult.getOrNull()
        if (metrolistData != null && metrolistData.streamUrl.isNotBlank()) {
            val transformed = prepareUrl(metrolistData.streamUrl)
            val metrolistClientName = metrolistData.clientName.ifBlank { "YTPlayerUtils.playerResponseForPlayback" }
            if (transformed != null && isRangePlayable(transformed, metrolistClientName, metrolistData.format.contentLength)) {
                return NativePlayback(
                    url = transformed,
                    mimeType = metrolistData.format.mimeType.substringBefore(";"),
                    bitrate = metrolistData.format.bitrate,
                    itag = metrolistData.format.itag,
                    expiresInSeconds = metrolistData.streamExpiresInSeconds,
                    contentLength = metrolistData.format.contentLength,
                    durationMs = ((metrolistData.videoDetails?.lengthSeconds ?: "0").toLongOrNull() ?: 0L) * 1000L,
                    title = metrolistData.videoDetails?.title ?: "",
                    source = metrolistClientName,
                )
            } else if (transformed != null) {
                Timber.tag(TAG).w("YTPlayerUtils returned a URL that failed byte validation for %s", videoId)
            }
        }

        resolveWithVerifiedNativeFallbacks(videoId, quality)?.let { return it }
        throw metrolistResult.exceptionOrNull()
            ?: IllegalStateException("Innertube do Metrolist não devolveu stream reproduzível")
    }

    private suspend fun resolveWithVerifiedNativeFallbacks(videoId: String, quality: AudioQuality): NativePlayback? {
        val clients = listOf(
            YouTubeClient.WEB_REMIX,
            YouTubeClient.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
            YouTubeClient.TVHTML5,
            YouTubeClient.ANDROID_VR_1_43_32,
            YouTubeClient.ANDROID_VR_1_61_48,
            YouTubeClient.ANDROID_CREATOR,
            YouTubeClient.IPADOS,
            YouTubeClient.ANDROID_VR_NO_AUTH,
            YouTubeClient.MOBILE,
            YouTubeClient.IOS,
            YouTubeClient.WEB,
            YouTubeClient.WEB_CREATOR,
        )

        for (client in clients) {
            val response = YouTube.player(
                videoId = videoId,
                playlistId = null,
                client = client,
                signatureTimestamp = null,
                poToken = null,
            ).getOrNull() ?: continue

            if (response.playabilityStatus.status != "OK") continue
            val formats = response.streamingData?.adaptiveFormats.orEmpty()
                .filter { it.isAudio }
                .sortedWith(formatComparator(quality))

            for (format in formats) {
                val candidateUrls = buildList {
                    runCatching { NewPipeExtractor.getStreamUrl(format, videoId) }
                        .getOrNull()
                        ?.trim()
                        ?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
                        ?.let(::add)

                    runCatching {
                        val signatureCipher = format.signatureCipher ?: format.cipher
                        if (signatureCipher.isNullOrBlank()) null
                        else CipherDeobfuscator.deobfuscateStreamUrl(signatureCipher, videoId)
                    }.getOrNull()
                        ?.trim()
                        ?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
                        ?.let(::add)

                    format.url
                        ?.trim()
                        ?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
                        ?.let { raw -> prepareUrl(raw) ?: raw }
                        ?.let(::add)
                }.distinct()

                for (candidate in candidateUrls) {
                    val prepared = prepareUrl(candidate) ?: continue
                    if (!isRangePlayable(prepared, client.clientName, format.contentLength)) {
                        Timber.tag(TAG).w("Skipping %s stream for %s because byte validation failed", client.clientName, videoId)
                        continue
                    }
                    return NativePlayback(
                        url = prepared,
                        mimeType = format.mimeType.substringBefore(";"),
                        bitrate = format.bitrate,
                        itag = format.itag,
                        expiresInSeconds = response.streamingData?.expiresInSeconds ?: 1800,
                        contentLength = format.contentLength,
                        durationMs = ((response.videoDetails?.lengthSeconds ?: "0").toLongOrNull() ?: 0L) * 1000L,
                        title = response.videoDetails?.title ?: "",
                        source = client.clientName,
                    )
                }
            }
        }

        val streamInfoUrls = runCatching { NewPipeExtractor.newPipePlayer(videoId) }.getOrDefault(emptyList())
        for ((itag, url) in streamInfoUrls) {
            if (!url.startsWith("http://") && !url.startsWith("https://")) continue
            val prepared = prepareUrl(url) ?: continue
            if (!isRangePlayable(prepared, "newpipe_streaminfo")) continue
            return NativePlayback(
                url = prepared,
                mimeType = "audio/webm",
                bitrate = 0,
                itag = itag,
                expiresInSeconds = 1800,
                contentLength = null,
                durationMs = 0L,
                title = "",
                source = "newpipe_streaminfo",
            )
        }

        return null
    }

    private fun isRangePlayable(url: String, source: String = "", contentLength: Long? = null): Boolean {
        val probes = mutableListOf(0L to 1L, 1_048_576L to 1_048_577L)
        val total = contentLength?.takeIf { it > 2_097_152L }
        if (total != null) {
            val middle = (total / 2).coerceAtLeast(1_048_576L)
            val nearEnd = (total - 65_536L).coerceAtLeast(0L)
            probes += middle to (middle + 1L).coerceAtMost(total - 1L)
            probes += nearEnd to (nearEnd + 1L).coerceAtMost(total - 1L)
        }
        var firstProbeOk = false
        for ((start, end) in probes.distinct()) {
            val ok = try {
                val builder = Request.Builder()
                    .url(url)
                    .get()
                    .header("Range", "bytes=$start-$end")
                    .header("Accept-Encoding", "identity")
                    .header("Accept", "*/*")
                    .header("User-Agent", userAgentForSource(source))
                YouTube.cookie?.let { builder.header("Cookie", it) }
                httpClient.newCall(builder.build()).execute().use { response ->
                    val success = response.code == 200 || response.code == 206
                    if (start == 0L) firstProbeOk = success
                    if (start > 0L && response.code == 416 && firstProbeOk) return true
                    if (!success) Timber.tag(TAG).w("Byte validation failed at %s-%s: HTTP %s source=%s", start, end, response.code, source)
                    success
                }
            } catch (e: Exception) {
                Timber.tag(TAG).w(e, "Byte validation exception at $start-$end source=$source")
                false
            }
            if (!ok) return false
        }
        return true
    }

    private suspend fun prepareUrl(rawUrl: String): String? {
        val url = rawUrl.trim()
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null
        val hasNParam = Regex("[?&]n=").containsMatchIn(url)
        if (!hasNParam) return url

        val transformed = runCatching { CipherDeobfuscator.transformNParamInUrl(url) }
            .onFailure { Timber.tag(TAG).w(it, "n-transform failed; rejecting throttled URL") }
            .getOrNull()
            ?: return null

        // If n= is still identical, the player JS transform was not actually applied.
        // Those URLs are exactly the ones that pass the first bytes and then return
        // HTTP 403 around 1 MB, which is why tracks stopped in the middle.
        if (transformed == url) {
            Timber.tag(TAG).w("n-transform returned the original URL; rejecting throttled URL")
            return null
        }
        return transformed
    }

    private fun formatComparator(quality: AudioQuality): Comparator<PlayerResponse.StreamingData.Format> = Comparator { a, b ->
        formatScore(b, quality).compareTo(formatScore(a, quality))
    }

    private fun formatScore(format: PlayerResponse.StreamingData.Format, quality: AudioQuality): Int {
        val bitrate = format.bitrate
        val target = when (quality) {
            AudioQuality.LOW -> 128_000
            AudioQuality.HIGH -> 256_000
            AudioQuality.VERY_HIGH -> 512_000
            AudioQuality.AUTO -> 256_000
        }
        val closeness = 1_000_000 - kotlin.math.abs(target - bitrate)
        val originalBonus = if (format.isOriginal) 250_000 else 0
        val audioBonus = when {
            format.mimeType.contains("mp4", ignoreCase = true) -> 180_000
            format.mimeType.contains("webm", ignoreCase = true) -> 140_000
            else -> 0
        }
        val cipherBonus = if (!format.signatureCipher.isNullOrBlank() || !format.cipher.isNullOrBlank()) 50_000 else 0
        return originalBonus + audioBonus + cipherBonus + closeness
    }

    internal fun userAgentForSource(source: String): String {
        val normalized = source.uppercase(Locale.US)
        return when {
            normalized.contains("IOS") || normalized.contains("IPADOS") ->
                "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)"
            normalized.contains("ANDROID") ->
                "com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip"
            else -> UPSTREAM_USER_AGENT
        }
    }

    internal const val UPSTREAM_USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
}

private object MetrolistNativeStreamServer {
    private const val TAG = "MetrolistNativeStreamServer"
    private const val CHUNK_LENGTH = 512 * 1024L

    @Volatile private var appContext: Context? = null
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var port: Int = -1

    fun urlFor(context: Context, videoId: String, qualityName: String): String {
        ensureStarted(context.applicationContext)
        val encodedId = encode(videoId)
        val encodedQuality = encode(qualityName)
        return "http://127.0.0.1:$port/stream?videoId=$encodedId&quality=$encodedQuality&t=${System.nanoTime()}"
    }

    private fun ensureStarted(context: Context) {
        if (serverSocket != null && port > 0) return
        synchronized(this) {
            if (serverSocket != null && port > 0) return
            appContext = context.applicationContext
            val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
            serverSocket = socket
            port = socket.localPort
            thread(name = "MetrolistNativeStreamServer", isDaemon = true, start = true) {
                while (!socket.isClosed) {
                    try {
                        val client = socket.accept()
                        thread(name = "MetrolistNativeStreamClient", isDaemon = true, start = true) {
                            handleClient(client)
                        }
                    } catch (e: Exception) {
                        if (!socket.isClosed) Timber.tag(TAG).w(e, "Accept failed")
                    }
                }
            }
            Timber.tag(TAG).i("Native stream server started on 127.0.0.1:$port")
        }
    }

    private fun handleClient(socket: Socket) {
        socket.soTimeout = 120_000
        try {
            val input = BufferedInputStream(socket.getInputStream())
            val output = BufferedOutputStream(socket.getOutputStream())
            val requestLine = readHttpLine(input) ?: return sendStatus(output, 400, "Bad Request")
            val parts = requestLine.split(" ")
            if (parts.size < 2) return sendStatus(output, 400, "Bad Request")

            val method = parts[0].uppercase(Locale.US)
            if (method != "GET" && method != "HEAD") {
                return sendStatus(output, 405, "Method Not Allowed")
            }

            val target = parts[1]
            val headers = readHeaders(input)
            val parsed = parseTarget(target)
            if (parsed.path != "/stream") return sendStatus(output, 404, "Not Found")

            // ExoPlayer sometimes logs/copies the query with the capital I in
            // videoId looking like a lowercase L. Older broken builds also emitted
            // videold. Accept every known spelling so the local stream never returns
            // a tiny text/plain 400 body that the player treats as silent EOS at 00:00.
            val videoId = firstQueryValue(parsed.query, "videoId", "videoid", "videold", "id", "v")
                ?.trim()
                .orEmpty()
            val quality = firstQueryValue(parsed.query, "quality", "q")
                ?.trim()
                .orEmpty()
                .ifBlank { "AUTO" }
            if (videoId.isBlank()) {
                Timber.tag(TAG).e("Missing videoId. target=%s query=%s", target, parsed.query)
                return sendStatus(output, 400, "Missing videoId")
            }

            val rangeHeader = headers["range"]
            val range = parseRange(rangeHeader)
            serveStream(
                output = output,
                videoId = videoId,
                quality = quality,
                start = range.first,
                requestedEnd = range.second,
                hasRange = !rangeHeader.isNullOrBlank(),
                headOnly = method == "HEAD",
                forceRefresh = false,
            )
        } catch (e: Exception) {
            val msg = e.message.orEmpty()
            if (e is SocketException || e.cause is SocketException ||
                e is java.io.IOException && (msg.contains("Broken pipe", true) || msg.contains("Connection reset", true))) {
                Timber.tag(TAG).d("Client closed local stream connection: ${e.message}")
            } else {
                try {
                    BufferedOutputStream(socket.getOutputStream()).use { output ->
                        sendStatus(output, 500, "Stream Error")
                    }
                } catch (_: Exception) {}
                Timber.tag(TAG).e(e, "Client handler failed")
            }
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun serveStream(
        output: BufferedOutputStream,
        videoId: String,
        quality: String,
        start: Long,
        requestedEnd: Long?,
        hasRange: Boolean,
        headOnly: Boolean,
        forceRefresh: Boolean,
    ) {
        val context = appContext ?: return sendStatus(output, 500, "Server not initialized")
        val safeStart = start.coerceAtLeast(0L)

        var playback = MetrolistStreamResolver.resolvePlaybackForProxy(context, videoId, quality, forceRefresh)

        // The local HTTP server mirrors Metrolist's playback core: resolve the
        // fresh googlevideo URL through Innertube/YTPlayerUtils, then serve the
        // player in small byte chunks. The HTTP response exposes exactly the
        // chunk it is serving, with honest Content-Range, so ExoPlayer keeps
        // requesting the next chunk instead of hanging at 00:00 or stopping when
        // googlevideo closes a long read halfway through a song.
        val firstChunkEnd = requestedEnd?.let { min(it, safeStart + CHUNK_LENGTH - 1) }
            ?: (safeStart + CHUNK_LENGTH - 1)
        val opened = openChunkWithRefresh(context, videoId, quality, playback, safeStart, firstChunkEnd)
        playback = opened.first
        val firstResponse = opened.second

        firstResponse.use { upstream ->
            when (upstream.code) {
                200, 206 -> {
                    val body = upstream.body
                    val upstreamContentRange = upstream.header("Content-Range")
                    val firstContentLength = upstream.header("Content-Length")
                        ?.toLongOrNull()
                        ?: body?.contentLength()?.takeIf { it >= 0 }
                    val contentType = upstream.header("Content-Type") ?: playback.mimeType.ifBlank { "audio/webm" }
                    val totalLength = listOfNotNull(
                        parseTotalLength(upstreamContentRange),
                        if (upstream.code == 200 && safeStart == 0L) firstContentLength?.takeIf { it > 0L } else null,
                        playback.contentLength?.takeIf { it > 0L },
                    ).firstOrNull()

                    // Match Metrolist's ResolvingDataSource behavior: every upstream
                    // request is a small CHUNK_LENGTH subrange. For HTTP/ExoPlayer we must
                    // also expose the response as that same small partial range; otherwise
                    // the player can wait for bytes we intentionally did not fetch yet or
                    // stop when a googlevideo connection closes mid-track.
                    val localChunkEnd = safeStart + CHUNK_LENGTH - 1
                    val responseEnd = when {
                        requestedEnd != null && totalLength != null -> min(min(requestedEnd, localChunkEnd), totalLength - 1)
                        requestedEnd != null -> min(requestedEnd, localChunkEnd)
                        totalLength != null -> min(localChunkEnd, totalLength - 1)
                        else -> localChunkEnd
                    }
                    val responseLength = (responseEnd - safeStart + 1).coerceAtLeast(0L)

                    val outHeaders = linkedMapOf(
                        "Content-Type" to contentType,
                        "Accept-Ranges" to "bytes",
                        "Connection" to "close",
                        "Cache-Control" to "no-store",
                        "X-Metrolist-Source" to playback.source,
                        "X-Metrolist-Itag" to playback.itag.toString(),
                    )

                    if (hasRange) {
                        outHeaders["Content-Range"] = "bytes $safeStart-$responseEnd/${totalLength?.toString() ?: "*"}"
                        outHeaders["Content-Length"] = responseLength.toString()
                        writeHeaders(output, 206, "Partial Content", outHeaders)
                    } else {
                        // Initial non-range requests are allowed to stream continuously.
                        // Once ExoPlayer starts seeking/range loading, the branch above
                        // gives it Metrolist-sized chunks with honest Content-Range.
                        if (totalLength != null && safeStart == 0L) {
                            outHeaders["Content-Length"] = totalLength.toString()
                        }
                        writeHeaders(output, 200, "OK", outHeaders)
                    }

                    if (headOnly || body == null) {
                        output.flush()
                        return
                    }

                    var nextStart = safeStart
                    var written = 0L
                    var emptyReads = 0

                    val firstLimit = (min(firstChunkEnd, responseEnd) - safeStart + 1).coerceAtLeast(0L)

                    val firstCopied = copyResponseBodyLimited(body, output, firstLimit)
                    written += firstCopied
                    nextStart += firstCopied
                    output.flush()

                    while (emptyReads < 5 && nextStart <= responseEnd) {
                        val nextEnd = min(nextStart + CHUNK_LENGTH - 1, responseEnd)
                        if (nextEnd < nextStart) break

                        val nextOpened = openChunkWithRefresh(context, videoId, quality, playback, nextStart, nextEnd)
                        playback = nextOpened.first
                        val nextResponse = nextOpened.second
                        if (nextResponse.code == 416) {
                            nextResponse.close()
                            break
                        }
                        if (nextResponse.code != 200 && nextResponse.code != 206) {
                            Timber.tag(TAG).e(
                                "Upstream HTTP %s for %s while streaming %s-%s",
                                nextResponse.code,
                                videoId,
                                nextStart,
                                nextEnd,
                            )
                            nextResponse.close()
                            emptyReads++
                            continue
                        }

                        val nextBody = nextResponse.body
                        if (nextBody == null) {
                            nextResponse.close()
                            emptyReads++
                            continue
                        }

                        val limit = (min(nextEnd, responseEnd) - nextStart + 1).coerceAtLeast(0L)

                        val copied = nextResponse.use { copyResponseBodyLimited(nextBody, output, limit) }
                        output.flush()
                        if (copied <= 0L) {
                            emptyReads++
                            continue
                        }

                        emptyReads = 0
                        written += copied
                        nextStart += copied

                        // The local HTTP response is one honest Metrolist-sized range.
                        // If upstream closes early, resume until this declared range is full.
                        if (copied < limit && nextStart > responseEnd) break
                    }

                    if (written < responseLength) {
                        Timber.tag(TAG).w(
                            "Local stream closed before full declared range for %s. written=%s expected=%s start=%s end=%s",
                            videoId,
                            written,
                            responseLength,
                            safeStart,
                            responseEnd,
                        )
                    }
                    output.flush()
                }
                416 -> sendStatus(output, 416, "Range Not Satisfiable")
                else -> {
                    Timber.tag(TAG).e("Upstream HTTP %s for %s", upstream.code, videoId)
                    sendStatus(output, 502, "Upstream HTTP ${upstream.code}")
                }
            }
        }
    }

    private fun copyResponseBody(body: okhttp3.ResponseBody, output: BufferedOutputStream): Long {
        var written = 0L
        body.byteStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = try {
                    stream.read(buffer)
                } catch (e: java.io.IOException) {
                    // GoogleVideo sometimes closes a range early. Do not mark the
                    // local response as complete; return the amount copied so the
                    // caller can resume from the exact missing byte.
                    Timber.tag(TAG).w(e, "Upstream read interrupted after %s bytes", written)
                    break
                }
                if (read <= 0) break
                output.write(buffer, 0, read)
                written += read.toLong()
            }
        }
        return written
    }

    private fun copyResponseBodyLimited(
        body: okhttp3.ResponseBody,
        output: BufferedOutputStream,
        maxBytes: Long,
    ): Long {
        var written = 0L
        if (maxBytes <= 0L) return 0L
        body.byteStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (written < maxBytes) {
                val remaining = (maxBytes - written).coerceAtMost(buffer.size.toLong()).toInt()
                val read = try {
                    stream.read(buffer, 0, remaining)
                } catch (e: java.io.IOException) {
                    Timber.tag(TAG).w(e, "Upstream read interrupted after %s/%s bytes", written, maxBytes)
                    break
                }
                if (read <= 0) break
                output.write(buffer, 0, read)
                written += read.toLong()
            }
        }
        return written
    }

    private fun openChunkWithRefresh(
        context: Context,
        videoId: String,
        quality: String,
        initialPlayback: MetrolistStreamResolver.NativePlayback,
        start: Long,
        end: Long,
    ): Pair<MetrolistStreamResolver.NativePlayback, okhttp3.Response> {
        var playback = initialPlayback
        repeat(5) { attempt ->
            val response = openUpstream(playback, start, end)
            val aligned = isAlignedUpstreamResponse(response, start)
            if (response.code != 403 && response.code != 404 && response.code != 410 && response.code != 416 && aligned) {
                return playback to response
            }
            Timber.tag(TAG).w(
                "Upstream %s for %s at %s-%s aligned=%s. Refreshing stream attempt %s.",
                response.code,
                videoId,
                start,
                end,
                aligned,
                attempt + 1,
            )
            response.close()
            MetrolistStreamResolver.invalidate(videoId)
            playback = MetrolistStreamResolver.resolvePlaybackForProxy(context, videoId, quality, forceRefresh = true)
        }
        return playback to openUpstream(playback, start, end)
    }

    private fun isAlignedUpstreamResponse(response: okhttp3.Response, requestedStart: Long): Boolean {
        if (response.code == 416) return true
        if (requestedStart <= 0L && response.code == 200) return true
        if (response.code != 206) {
            // If a later chunk ignores Range and returns 200, copying it would repeat
            // bytes from the start of the file and corrupt playback/seek.
            return false
        }
        val actualStart = parseContentRangeStart(response.header("Content-Range"))
        return actualStart == null || actualStart == requestedStart
    }

    private fun openUpstream(
        playback: MetrolistStreamResolver.NativePlayback,
        start: Long,
        end: Long,
    ): okhttp3.Response {
        val safeEnd = end.coerceAtLeast(start)
        val builder = Request.Builder()
            .url(playback.url)
            .get()
            .header("Range", "bytes=$start-$safeEnd")
            .header("Accept-Encoding", "identity")
            .header("Accept", "*/*")
            .header("User-Agent", userAgentForSource(playback.source))

        YouTube.cookie?.let { builder.header("Cookie", it) }
        return MetrolistStreamResolver.httpClient.newCall(builder.build()).execute()
    }

    private fun userAgentForSource(source: String): String {
        val normalized = source.uppercase(Locale.US)
        return when {
            normalized.contains("IOS") || normalized.contains("IPADOS") ->
                "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)"
            normalized.contains("ANDROID") ->
                "com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip"
            else -> MetrolistStreamResolver.UPSTREAM_USER_AGENT
        }
    }

    private fun parseTotalLength(contentRange: String?): Long? {
        if (contentRange.isNullOrBlank()) return null
        val total = contentRange.substringAfter("/", "").trim()
        return total.takeIf { it.isNotBlank() && it != "*" }?.toLongOrNull()
    }

    private fun parseContentRangeStart(contentRange: String?): Long? {
        if (contentRange.isNullOrBlank()) return null
        return contentRange.substringAfter("bytes", "")
            .substringBefore("/")
            .substringBefore("-")
            .trim()
            .toLongOrNull()
    }

    private fun parseContentRangeEnd(contentRange: String?): Long? {
        if (contentRange.isNullOrBlank()) return null
        return contentRange.substringAfter("-", "")
            .substringBefore("/")
            .trim()
            .toLongOrNull()
    }

    private fun buildContentRange(start: Long, end: Long?, total: Long?): String? {
        val safeEnd = end ?: return null
        val totalPart = total?.toString() ?: "*"
        return "bytes $start-$safeEnd/$totalPart"
    }

    private fun parseRange(range: String?): Pair<Long, Long?> {
        if (range.isNullOrBlank()) return 0L to null
        val normalized = range.lowercase(Locale.US).trim()
        if (!normalized.startsWith("bytes=")) return 0L to null
        val value = normalized.removePrefix("bytes=").substringBefore(",")
        val start = value.substringBefore("-").trim().toLongOrNull()?.coerceAtLeast(0L) ?: 0L
        val end = value.substringAfter("-", "").trim().toLongOrNull()?.coerceAtLeast(start)
        return start to end
    }

    private data class ParsedTarget(val path: String, val query: Map<String, String>)

    private fun firstQueryValue(query: Map<String, String>, vararg names: String): String? {
        for (name in names) {
            query[name]?.let { return it }
        }
        for ((key, value) in query) {
            if (names.any { wanted -> key.equals(wanted, ignoreCase = true) }) {
                return value
            }
        }
        return null
    }

    private fun parseTarget(target: String): ParsedTarget {
        val path = target.substringBefore("?")
        val queryString = target.substringAfter("?", "")
        val query = mutableMapOf<String, String>()
        if (queryString.isNotBlank()) {
            queryString.split("&").forEach { part ->
                val key = decode(part.substringBefore("=", ""))
                val value = decode(part.substringAfter("=", ""))
                if (key.isNotBlank()) query[key] = value
            }
        }
        return ParsedTarget(path, query)
    }

    private fun readHeaders(input: BufferedInputStream): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = readHttpLine(input) ?: break
            if (line.isEmpty()) break
            val idx = line.indexOf(':')
            if (idx > 0) {
                headers[line.substring(0, idx).trim().lowercase(Locale.US)] = line.substring(idx + 1).trim()
            }
        }
        return headers
    }

    private fun readHttpLine(input: BufferedInputStream): String? {
        val bytes = ArrayList<Byte>(128)
        while (true) {
            val next = input.read()
            if (next == -1) return if (bytes.isEmpty()) null else bytes.toByteArray().toString(StandardCharsets.UTF_8)
            if (next == '\n'.code) break
            if (next != '\r'.code) bytes.add(next.toByte())
            if (bytes.size > 8192) break
        }
        return bytes.toByteArray().toString(StandardCharsets.UTF_8)
    }

    private fun sendStatus(output: BufferedOutputStream, code: Int, text: String) {
        val body = "$code $text\n".toByteArray(StandardCharsets.UTF_8)
        writeHeaders(
            output,
            code,
            text,
            mapOf(
                "Content-Type" to "text/plain; charset=utf-8",
                "Content-Length" to body.size.toString(),
                "Connection" to "close",
                "Cache-Control" to "no-store",
            ),
        )
        output.write(body)
        output.flush()
    }

    private fun writeHeaders(output: BufferedOutputStream, code: Int, text: String, headers: Map<String, String>) {
        output.write("HTTP/1.1 $code $text\r\n".toByteArray(StandardCharsets.UTF_8))
        headers.forEach { (key, value) ->
            output.write("$key: $value\r\n".toByteArray(StandardCharsets.UTF_8))
        }
        output.write("\r\n".toByteArray(StandardCharsets.UTF_8))
    }

    private fun encode(value: String): String = java.net.URLEncoder.encode(value, StandardCharsets.UTF_8.name())

    private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())
}
