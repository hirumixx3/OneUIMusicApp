package com.metrolist.music.utils.cipher

import com.metrolist.innertube.YouTube
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import timber.log.Timber
import java.io.File

/**
 * Fetches and caches YouTube's player.js for cipher operations.
 *
 * The player.js contains the signature deobfuscation and n-transform functions
 * that are required to access stream URLs on web clients.
 */
object PlayerJsFetcher {
    private const val TAG = "Metrolist_CipherFetcher"
    private const val IFRAME_API_URL = "https://www.youtube.com/iframe_api"
    private const val YOUTUBE_HOME_URL = "https://www.youtube.com/"
    private const val YOUTUBE_MUSIC_HOME_URL = "https://music.youtube.com/"
    private const val PLAYER_JS_URL_TEMPLATE = "https://www.youtube.com/s/player/%s/player_ias.vflset/en_GB/base.js"
    private const val CACHE_TTL_MS = 6 * 60 * 60 * 1000L // 6 hours

    private val httpClient = OkHttpClient.Builder()
        .proxy(YouTube.proxy)
        .build()

    // Regex to extract player hash from iframe_api response
    private val PLAYER_HASH_REGEXES = listOf(
        Regex("""/s/player/([a-zA-Z0-9_-]+)/"""),
        Regex("""/s/player/([a-zA-Z0-9_-]+)/player_ias\.vflset/[^/]+/base\.js"""),
        Regex("""player/([a-zA-Z0-9_-]+)/"""),
        Regex("""player_ias\.vflset/[^/]+/([a-zA-Z0-9_-]+)/"""),
        Regex("""\"jsUrl\"\s*:\s*\"/s/player/([a-zA-Z0-9_-]+)/"""),
        Regex("""\"PLAYER_JS_URL\"\s*:\s*\"/s/player/([a-zA-Z0-9_-]+)/"""),
    )

    private val PLAYER_JS_URL_REGEXES = listOf(
        Regex("""https?://(?:www\.)?youtube\.com/s/player/[a-zA-Z0-9_-]+/player_ias\.vflset/[^"'\\<>\s]+/base\.js"""),
        Regex("""/s/player/[a-zA-Z0-9_-]+/player_ias\.vflset/[^"'\\<>\s]+/base\.js"""),
        Regex("""/s/player/[a-zA-Z0-9_-]+/[^"'\\<>\s]*base\.js"""),
    )

    private fun getCacheDir(): File = File(CipherDeobfuscator.appContext.filesDir, "cipher_cache")

    private fun getCacheFile(hash: String): File = File(getCacheDir(), "player_$hash.js")

    private fun getHashFile(): File = File(getCacheDir(), "current_hash.txt")

    /**
     * Get player.js content and hash.
     *
     * Uses cached version if available and not expired, otherwise fetches fresh.
     * Returns Pair(playerJs, hash) or null if failed.
     */
    suspend fun getPlayerJs(forceRefresh: Boolean = false): Pair<String, String>? = withContext(Dispatchers.IO) {
        Timber.tag(TAG).d("=== GET PLAYER.JS ===")
        Timber.tag(TAG).d("forceRefresh: $forceRefresh")

        try {
            val cacheDir = getCacheDir()
            if (!cacheDir.exists()) {
                Timber.tag(TAG).d("Creating cache directory: ${cacheDir.absolutePath}")
                cacheDir.mkdirs()
            }

            // Check cache first (unless forced refresh)
            if (!forceRefresh) {
                val cached = readFromCache()
                if (cached != null) {
                    Timber.tag(TAG).d("=== CACHE HIT ===")
                    Timber.tag(TAG).d("Using cached player JS (hash=${cached.second}, length=${cached.first.length})")
                    return@withContext cached
                }
                Timber.tag(TAG).d("Cache miss, will fetch fresh")
            }

            // Fetch player JS. YouTube's iframe_api stopped exposing the
            // player hash reliably, so first try direct player JS discovery from
            // iframe/home/music pages and only then fall back to the old hash URL.
            Timber.tag(TAG).d("Discovering player JS...")
            val discovered = discoverAndDownloadPlayerJs()
            val hash = discovered?.second ?: fetchPlayerHash()
            if (hash == null) {
                Timber.tag(TAG).e("Failed to discover player hash/player JS")
                return@withContext null
            }
            Timber.tag(TAG).d("Extracted player hash: $hash")

            val playerJs = discovered?.first ?: downloadPlayerJs(hash)
            if (playerJs == null) {
                Timber.tag(TAG).e("Failed to download player JS for hash=$hash")
                return@withContext null
            }

            Timber.tag(TAG).d("=== PLAYER.JS DOWNLOADED ===")
            Timber.tag(TAG).d("hash: $hash")
            Timber.tag(TAG).d("length: ${playerJs.length} chars")
            Timber.tag(TAG).d("preview: ${playerJs.take(100)}...")

            // Cache the result
            writeToCache(hash, playerJs)

            Pair(playerJs, hash)
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "getPlayerJs exception: ${e.message}")
            null
        }
    }

    /**
     * Invalidate the player.js cache.
     * Call this when cipher operations fail to force a fresh fetch.
     */
    fun invalidateCache() {
        Timber.tag(TAG).d("Invalidating cache...")
        try {
            val cacheDir = getCacheDir()
            if (cacheDir.exists()) {
                val files = cacheDir.listFiles()
                Timber.tag(TAG).d("Deleting ${files?.size ?: 0} cache files")
                files?.forEach {
                    Timber.tag(TAG).v("Deleting: ${it.name}")
                    it.delete()
                }
            }
            Timber.tag(TAG).d("Cache invalidated successfully")
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Failed to invalidate cache: ${e.message}")
        }
    }

    private fun readFromCache(): Pair<String, String>? {
        Timber.tag(TAG).d("Checking cache...")
        try {
            val hashFile = getHashFile()
            if (!hashFile.exists()) {
                Timber.tag(TAG).d("Hash file does not exist")
                return null
            }

            val hashData = hashFile.readText().split("\n")
            if (hashData.size < 2) {
                Timber.tag(TAG).d("Hash file malformed (expected 2 lines, got ${hashData.size})")
                return null
            }

            val hash = hashData[0]
            val timestamp = hashData[1].toLongOrNull()
            if (timestamp == null) {
                Timber.tag(TAG).d("Could not parse timestamp from hash file")
                return null
            }

            val ageMs = System.currentTimeMillis() - timestamp
            val ageHours = ageMs / (1000 * 60 * 60)
            Timber.tag(TAG).d("Cache age: ${ageHours}h (TTL: ${CACHE_TTL_MS / (1000 * 60 * 60)}h)")

            // Check TTL
            if (ageMs > CACHE_TTL_MS) {
                Timber.tag(TAG).d("Cache expired (hash=$hash, age=${ageHours}h)")
                return null
            }

            val cacheFile = getCacheFile(hash)
            if (!cacheFile.exists()) {
                Timber.tag(TAG).d("Cache file does not exist for hash: $hash")
                return null
            }

            val playerJs = cacheFile.readText()
            if (playerJs.isEmpty()) {
                Timber.tag(TAG).d("Cache file is empty")
                return null
            }

            Timber.tag(TAG).d("Cache valid: hash=$hash, length=${playerJs.length}, age=${ageHours}h")
            return Pair(playerJs, hash)
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Error reading cache: ${e.message}")
            return null
        }
    }

    private fun writeToCache(hash: String, playerJs: String) {
        Timber.tag(TAG).d("Writing to cache: hash=$hash, length=${playerJs.length}")
        try {
            val cacheDir = getCacheDir()

            // Clean old cache files
            val oldFiles = cacheDir.listFiles()?.filter { it.name.startsWith("player_") }
            Timber.tag(TAG).d("Cleaning ${oldFiles?.size ?: 0} old cache files")
            oldFiles?.forEach { it.delete() }

            getCacheFile(hash).writeText(playerJs)
            getHashFile().writeText("$hash\n${System.currentTimeMillis()}")

            Timber.tag(TAG).d("Cache written successfully")
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Error writing cache: ${e.message}")
        }
    }

    private fun discoverAndDownloadPlayerJs(): Pair<String, String>? {
        val discoveryPages = listOf(IFRAME_API_URL, YOUTUBE_HOME_URL, YOUTUBE_MUSIC_HOME_URL)
        for (pageUrl in discoveryPages) {
            val body = fetchText(pageUrl) ?: continue
            extractPlayerJsUrls(body).forEach { playerUrl ->
                val hash = extractHashFromPlayerUrl(playerUrl) ?: return@forEach
                val playerJs = downloadUrl(playerUrl)
                if (!playerJs.isNullOrBlank()) {
                    Timber.tag(TAG).d("Discovered player JS from %s hash=%s length=%s", pageUrl, hash, playerJs.length)
                    return Pair(playerJs, hash)
                }
            }

            val hash = extractHashFromText(body)
            if (hash != null) {
                val playerJs = downloadPlayerJs(hash)
                if (!playerJs.isNullOrBlank()) {
                    Timber.tag(TAG).d("Discovered player hash from %s hash=%s", pageUrl, hash)
                    return Pair(playerJs, hash)
                }
            }
        }
        return null
    }

    private fun fetchText(url: String): String? = downloadUrl(url)

    private fun downloadUrl(url: String): String? {
        val normalizedUrl = if (url.startsWith("//")) "https:$url" else if (url.startsWith("/")) "https://www.youtube.com$url" else url
        return try {
            val request = Request.Builder()
                .url(normalizedUrl)
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")
                .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .header("Accept-Language", "en-US,en;q=0.9")
                .build()
            httpClient.newCall(request).execute().use { response ->
                Timber.tag(TAG).d("downloadUrl %s -> HTTP %s", normalizedUrl, response.code)
                if (!response.isSuccessful) return null
                response.body?.string()
            }
        } catch (e: Exception) {
            Timber.tag(TAG).w(e, "downloadUrl failed: $normalizedUrl")
            null
        }
    }

    private fun extractPlayerJsUrls(body: String): List<String> {
        val urls = linkedSetOf<String>()
        PLAYER_JS_URL_REGEXES.forEach { regex ->
            regex.findAll(body).forEach { match ->
                val raw = match.value
                    .replace("\\/", "/")
                    .replace("\\u0026", "&")
                val url = when {
                    raw.startsWith("http://") || raw.startsWith("https://") -> raw
                    raw.startsWith("//") -> "https:$raw"
                    raw.startsWith("/") -> "https://www.youtube.com$raw"
                    else -> raw
                }
                urls += url
            }
        }
        Timber.tag(TAG).d("extractPlayerJsUrls found %s candidates", urls.size)
        return urls.toList()
    }

    private fun extractHashFromText(body: String): String? {
        for (regex in PLAYER_HASH_REGEXES) {
            val match = regex.find(body)
            if (match != null) return match.groupValues[1]
        }
        return null
    }

    private fun extractHashFromPlayerUrl(url: String): String? =
        Regex("""/s/player/([a-zA-Z0-9_-]+)/""").find(url)?.groupValues?.getOrNull(1)

    private fun fetchPlayerHash(): String? {
        Timber.tag(TAG).d("Fetching iframe_api from: $IFRAME_API_URL")
        val body = fetchText(IFRAME_API_URL)
        if (body == null) {
            Timber.tag(TAG).e("iframe_api response body is null")
            return null
        }
        Timber.tag(TAG).d("iframe_api body length: ${body.length}")
        Timber.tag(TAG).v("iframe_api body preview: ${body.take(200)}...")
        val hash = extractHashFromText(body)
        if (hash != null) {
            Timber.tag(TAG).d("Found player hash: $hash")
            return hash
        }
        Timber.tag(TAG).e("Could not find player hash in iframe_api response")
        Timber.tag(TAG).d("Tried patterns: ${PLAYER_HASH_REGEXES.joinToString { it.pattern }}")
        return null
    }

    private fun downloadPlayerJs(hash: String): String? {
        val url = PLAYER_JS_URL_TEMPLATE.format(hash)
        Timber.tag(TAG).d("Downloading player.js from: $url")
        val body = downloadUrl(url)
        if (body == null) {
            Timber.tag(TAG).e("player.js download failed for hash=$hash")
            return null
        }
        Timber.tag(TAG).d("player.js downloaded: ${body.length} chars")
        return body
    }

    /**
     * Debug method: Get cache information
     */
    fun getCacheInfo(): Map<String, Any?> {
        return try {
            val hashFile = getHashFile()
            if (!hashFile.exists()) {
                return mapOf("exists" to false)
            }

            val hashData = hashFile.readText().split("\n")
            val hash = hashData.getOrNull(0)
            val timestamp = hashData.getOrNull(1)?.toLongOrNull()
            val cacheFile = hash?.let { getCacheFile(it) }

            mapOf(
                "exists" to true,
                "hash" to hash,
                "timestamp" to timestamp,
                "ageMs" to (timestamp?.let { System.currentTimeMillis() - it }),
                "fileExists" to (cacheFile?.exists() == true),
                "fileSize" to (cacheFile?.length()),
            )
        } catch (e: Exception) {
            mapOf("error" to e.message)
        }
    }
}
