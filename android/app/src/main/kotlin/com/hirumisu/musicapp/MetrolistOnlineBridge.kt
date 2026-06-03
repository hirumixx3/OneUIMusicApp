package com.hirumisu.musicapp

import android.content.Context
import com.metrolist.innertube.YouTube
import com.metrolist.innertube.models.AlbumItem
import com.metrolist.innertube.models.ArtistItem
import com.metrolist.innertube.models.BrowseEndpoint
import com.metrolist.innertube.models.PlaylistItem
import com.metrolist.innertube.models.PodcastItem
import com.metrolist.innertube.models.SongItem
import com.metrolist.innertube.models.YTItem
import com.metrolist.innertube.models.filterVideoSongs
import com.metrolist.music.utils.cipher.CipherDeobfuscator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.concurrent.TimeUnit
import timber.log.Timber

/**
 * Online catalog bridge backed only by Metrolist's native Innertube module.
 * Dart no longer calls YouTube Music HTTP/json parsing.
 */
object MetrolistOnlineBridge {
    @Volatile private var initialized = false
    private val quickHttpClient by lazy {
        MetrolistStreamResolver.httpClient.newBuilder()
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(6, TimeUnit.SECONDS)
            .writeTimeout(6, TimeUnit.SECONDS)
            .build()
    }

    private fun ensureInitialized(context: Context) {
        if (!initialized) {
            synchronized(this) {
                if (!initialized) {
                    if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
                    MetrolistYouTubeSession.restore(context.applicationContext, blockForVisitor = false)
                    CipherDeobfuscator.initialize(context.applicationContext)
                    initialized = true
                }
            }
        }
    }

    fun home(context: Context): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val seeds = listOf(
            "top músicas brasil",
            "lançamentos brasil",
            "músicas virais",
            "sertanejo hits",
            "funk atual",
            "pop hits",
            "kpop hits",
            "relax music",
            "playlist brasil",
        )
        val homeDeferred = async {
            withTimeoutOrNull(4500L) {
                runCatching { YouTube.home().getOrThrow().sections.flatMap { it.items } }.getOrDefault(emptyList<YTItem>())
            } ?: emptyList<YTItem>()
        }
        val seedDeferred = seeds.map { seed ->
            async {
                withTimeoutOrNull(4500L) {
                    runCatching { YouTube.searchSummary(seed).getOrThrow().summaries.flatMap { it.items } }.getOrDefault(emptyList<YTItem>())
                } ?: emptyList<YTItem>()
            }
        }
        val collected = mutableListOf<YTItem>()
        collected += homeDeferred.await()
        // Busca paralela: evita a tela Online ficar vazia/lenta quando home()
        // devolve pouco conteúdo ou demora em algumas contas/regiões.
        seedDeferred.awaitAll().forEach { collected += it }
        searchResultMap(collected.dedupeItems())
    }



    private fun queryVariants(query: String): List<String> {
        val cleaned = query.trim().replace(Regex("\\s+"), " ")
        if (cleaned.isBlank()) return emptyList()
        val fixed = cleaned
            .replace(Regex("\\bchassing\\b", RegexOption.IGNORE_CASE), "chasing")
            .replace(Regex("\\bfelling\\b", RegexOption.IGNORE_CASE), "feeling")
            .replace(Regex("\\bfeelling\\b", RegexOption.IGNORE_CASE), "feeling")
        val variants = linkedSetOf<String>()
        fun add(value: String) {
            val v = value.trim().replace(Regex("\\s+"), " ")
            if (v.isNotBlank()) variants += v
        }
        add(cleaned)
        add(fixed)
        if (fixed.equals("txt", ignoreCase = true) || fixed.equals("t x t", ignoreCase = true)) {
            add("TOMORROW X TOGETHER")
            add("Tomorrow X Together")
        }
        if (!fixed.contains("music", ignoreCase = true) && !fixed.contains("música", ignoreCase = true)) {
            add("$fixed música")
            add("$fixed song")
        }
        return variants.toList()
    }

    private fun expandedSongQueries(query: String): List<String> {
        val base = queryVariants(query)
        val expanded = linkedSetOf<String>()
        fun add(value: String) {
            val v = value.trim().replace(Regex("\\s+"), " ")
            if (v.isNotBlank()) expanded += v
        }
        for (variant in base) {
            add(variant)
            add("$variant official audio")
            add("$variant topic")
            add("$variant audio")
            add("$variant lyrics")
            add("$variant album")
        }
        return expanded.toList()
    }

    private const val SYNTHETIC_CONTINUATION_PREFIX = "APP_MORE::"

    private fun syntheticContinuation(query: String, page: Int): String =
        SYNTHETIC_CONTINUATION_PREFIX + URLEncoder.encode(query, StandardCharsets.UTF_8.name()) + "::" + page

    private fun parseSyntheticContinuation(token: String): Pair<String, Int>? {
        if (!token.startsWith(SYNTHETIC_CONTINUATION_PREFIX)) return null
        val raw = token.removePrefix(SYNTHETIC_CONTINUATION_PREFIX)
        val split = raw.lastIndexOf("::")
        if (split <= 0) return null
        val query = runCatching { URLDecoder.decode(raw.substring(0, split), StandardCharsets.UTF_8.name()) }.getOrNull() ?: return null
        val page = raw.substring(split + 2).toIntOrNull() ?: return null
        return query to page.coerceAtLeast(1)
    }


    private fun decodeWebText(value: String?): String {
        if (value.isNullOrBlank()) return ""
        return value
            .replace("\\u0026", "&")
            .replace("\\/", "/")
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("\\n", " ")
            .replace(Regex("\\\\u([0-9a-fA-F]{4})")) { match ->
                runCatching { match.groupValues[1].toInt(16).toChar().toString() }.getOrDefault(match.value)
            }
            .trim()
    }

    private fun parseDurationMs(value: String?): Long {
        val text = decodeWebText(value).trim()
        if (text.isBlank()) return 0L
        val parts = text.split(':').mapNotNull { it.trim().toLongOrNull() }
        if (parts.isEmpty()) return 0L
        var seconds = 0L
        for (part in parts) seconds = seconds * 60L + part
        return seconds * 1000L
    }

    private fun fallbackSongMap(
        id: String,
        title: String,
        artist: String,
        thumbnail: String,
        durationMs: Long = 0L,
    ): Map<String, Any?> = mapOf(
        "id" to id,
        "uri" to "",
        "title" to title.ifBlank { "YouTube Music" },
        "artist" to artist.ifBlank { "YouTube Music" },
        "album" to "YouTube Music",
        "duration" to durationMs,
        "path" to "",
        "mimeType" to "audio/webm",
        "dateAdded" to 0,
        "dateModified" to 0,
        "artworkUrl" to highQualityThumbnail(thumbnail.ifBlank { "https://i.ytimg.com/vi/$id/hqdefault.jpg" }),
        "isRemote" to true,
        "remoteStreamUri" to "",
        "videoId" to id,
        "artistId" to null,
        "browseId" to null,
        "trackNumber" to null,
    )

    private fun mergeSongMaps(items: List<Map<String, Any?>>): List<Map<String, Any?>> =
        items.distinctBy { (it["videoId"] ?: it["id"] ?: it["title"]).toString() }

    private fun isLikelyBadWebResult(title: String, artist: String): Boolean {
        val text = "$title $artist".lowercase(Locale.ROOT)
        if (text.contains("reaction") || text.contains("tutorial") || text.contains("karaoke")) return true
        if (text.contains("cover") && !text.contains("official")) return true
        if (text.contains("podcast") || text.contains("interview")) return true
        return false
    }

    private fun webSearchQueries(query: String, page: Int): List<String> {
        val base = expandedSongQueries(query).ifEmpty { queryVariants(query) }
        val suffixes = listOf(
            "official audio", "topic", "lyrics", "song", "audio", "album", "music", "official", "live", "remix", "playlist", "full album",
        )
        val all = linkedSetOf<String>()
        base.forEach { all += it }
        queryVariants(query).forEach { q -> suffixes.forEach { suffix -> all += "$q $suffix" } }
        val start = (page.coerceAtLeast(0) * 3).coerceAtMost(all.size)
        return all.drop(start).take(3).ifEmpty { queryVariants(query).take(1) }
    }

    private fun JSONObject.findObjectKeys(name: String, out: MutableList<JSONObject>) {
        val keys = keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = opt(key)
            if (key == name && value is JSONObject) out += value
            when (value) {
                is JSONObject -> value.findObjectKeys(name, out)
                is JSONArray -> value.findObjectKeys(name, out)
            }
        }
    }

    private fun JSONArray.findObjectKeys(name: String, out: MutableList<JSONObject>) {
        for (i in 0 until length()) {
            when (val value = opt(i)) {
                is JSONObject -> value.findObjectKeys(name, out)
                is JSONArray -> value.findObjectKeys(name, out)
            }
        }
    }

    private fun runsText(obj: JSONObject?): String {
        if (obj == null) return ""
        val runs = obj.optJSONArray("runs") ?: return decodeWebText(obj.optString("simpleText", ""))
        val parts = mutableListOf<String>()
        for (i in 0 until runs.length()) {
            val text = runs.optJSONObject(i)?.optString("text", "").orEmpty()
            if (text.isNotBlank() && text != "•" && text != "·") parts += decodeWebText(text)
        }
        return parts.joinToString(" ").replace(Regex("\\s+"), " ").trim()
    }

    private fun parseMusicResponsiveSong(renderer: JSONObject): Map<String, Any?>? {
        val id = renderer.optJSONObject("playlistItemData")?.optString("videoId")?.takeIf { it.isNotBlank() }
            ?: renderer.optJSONObject("overlay")
                ?.optJSONObject("musicItemThumbnailOverlayRenderer")
                ?.optJSONObject("content")
                ?.optJSONObject("musicPlayButtonRenderer")
                ?.optJSONObject("playNavigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.isNotBlank() }
            ?: renderer.optJSONObject("navigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.isNotBlank() }
            ?: return null
        val columns = renderer.optJSONArray("flexColumns") ?: return null
        val title = runsText(
            columns.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
        )
        if (title.isBlank()) return null
        val subtitle = runsText(
            columns.optJSONObject(1)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
        )
        val parts = subtitle.split(Regex("\\s+[•·]\\s+|\\s+•\\s+|\\s+·\\s+")).map { it.trim() }.filter { it.isNotBlank() }
        val artist = parts.firstOrNull { part ->
            val low = part.lowercase(Locale.ROOT)
            low !in setOf("song", "songs", "video", "videos", "music video", "album", "single", "playlist", "música", "vídeo") &&
                !low.contains("views") && !low.contains("visualizações") && !low.matches(Regex("\\d+:\\d+"))
        } ?: parts.firstOrNull().orEmpty()
        val thumbs = renderer.optJSONObject("thumbnail")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?.optJSONArray("thumbnails")
        val thumb = if (thumbs != null && thumbs.length() > 0) {
            thumbs.optJSONObject(thumbs.length() - 1)?.optString("url", "").orEmpty()
        } else ""
        val durationText = parts.lastOrNull { it.matches(Regex("\\d{1,2}:\\d{2}(?::\\d{2})?")) }.orEmpty()
        if (isLikelyBadWebResult(title, artist)) return null
        return fallbackSongMap(id, title, artist, thumb, parseDurationMs(durationText))
    }

    private fun fetchInnertubeRawSongMaps(query: String, page: Int = 0, limit: Int = 80): List<Map<String, Any?>> {
        val collected = mutableListOf<Map<String, Any?>>()
        val apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3"
        val params = YouTube.SearchFilter.FILTER_SONG.value
        for (variant in webSearchQueries(query, page)) {
            val body = JSONObject()
                .put("context", JSONObject()
                    .put("client", JSONObject()
                        .put("clientName", "WEB_REMIX")
                        .put("clientVersion", "1.20240520.01.00")
                        .put("hl", "pt")
                        .put("gl", "BR")
                    )
                    .put("user", JSONObject().put("lockedSafetyMode", false))
                    .put("request", JSONObject().put("useSsl", true))
                )
                .put("query", variant)
                .put("params", params)
                .toString()
            val raw = runCatching {
                val requestBody = body.toRequestBody("application/json; charset=utf-8".toMediaType())
                val request = Request.Builder()
                    .url("https://music.youtube.com/youtubei/v1/search?prettyPrint=false&key=$apiKey")
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
                    .header("Origin", "https://music.youtube.com")
                    .header("Referer", "https://music.youtube.com/search?q=${URLEncoder.encode(variant, StandardCharsets.UTF_8.name())}")
                    .header("Content-Type", "application/json")
                    .post(requestBody)
                    .build()
                quickHttpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) "" else response.body?.string().orEmpty()
                }
            }.getOrDefault("")
            if (raw.isBlank()) continue
            val renderers = mutableListOf<JSONObject>()
            runCatching { JSONObject(raw).findObjectKeys("musicResponsiveListItemRenderer", renderers) }
            for (renderer in renderers) {
                parseMusicResponsiveSong(renderer)?.let { collected += it }
                if (mergeSongMaps(collected).size >= limit) break
            }
            if (mergeSongMaps(collected).size >= limit) break
        }
        return mergeSongMaps(collected).take(limit)
    }

    private fun fetchYoutubeWebSongMaps(query: String, page: Int = 0, limit: Int = 60): List<Map<String, Any?>> {
        if (query.isBlank()) return emptyList()
        val direct = fetchInnertubeRawSongMaps(query, page = page, limit = limit)
        if (direct.size >= (limit / 3).coerceAtLeast(8)) return direct.take(limit)
        val collected = mutableListOf<Map<String, Any?>>()
        collected += direct
        val seen = linkedSetOf<String>()
        direct.forEach { seen += (it["videoId"] ?: it["id"] ?: "").toString() }
        for (variant in webSearchQueries(query, page)) {
            val encoded = URLEncoder.encode(variant, StandardCharsets.UTF_8.name())
            val urls = listOf(
                "https://www.youtube.com/results?search_query=$encoded",
                "https://music.youtube.com/search?q=$encoded",
            )
            for (url in urls) {
                val body = runCatching {
                    val request = Request.Builder()
                        .url(url)
                        .header("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
                        .header("Accept-Language", "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7")
                        .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                        .get()
                        .build()
                    quickHttpClient.newCall(request).execute().use { response ->
                        if (!response.isSuccessful) "" else response.body?.string().orEmpty()
                    }
                }.getOrDefault("")
                if (body.isBlank()) continue
                val matches = Regex("\\\"videoId\\\":\\\"([A-Za-z0-9_-]{11})\\\"").findAll(body)
                for (match in matches) {
                    val id = match.groupValues[1]
                    if (!seen.add(id)) continue
                    val start = (match.range.first - 2500).coerceAtLeast(0)
                    val end = (match.range.first + 9000).coerceAtMost(body.length)
                    val block = body.substring(start, end)
                    val title = decodeWebText(
                        Regex("\\\"title\\\"\\s*:\\s*\\{\\s*\\\"runs\\\"\\s*:\\s*\\[\\s*\\{\\s*\\\"text\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
                            .find(block)?.groupValues?.getOrNull(1)
                            ?: Regex("\\\"title\\\"\\s*:\\s*\\{\\s*\\\"simpleText\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
                                .find(block)?.groupValues?.getOrNull(1)
                    )
                    val artist = decodeWebText(
                        Regex("\\\"longBylineText\\\".*?\\\"text\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
                            .find(block)?.groupValues?.getOrNull(1)
                            ?: Regex("\\\"shortBylineText\\\".*?\\\"text\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
                                .find(block)?.groupValues?.getOrNull(1)
                            ?: Regex("\\\"ownerText\\\".*?\\\"text\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
                                .find(block)?.groupValues?.getOrNull(1)
                    )
                    val thumb = decodeWebText(
                        Regex("\\\"url\\\"\\s*:\\s*\\\"([^\\\"]*i\\.ytimg\\.com[^\\\"]+)\\\"")
                            .find(block)?.groupValues?.getOrNull(1)
                    )
                    val duration = parseDurationMs(
                        Regex("\\\"lengthText\\\".*?\\\"simpleText\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
                            .find(block)?.groupValues?.getOrNull(1)
                    )
                    if (title.isBlank()) continue
                    if (isLikelyBadWebResult(title, artist)) continue
                    collected += fallbackSongMap(id, title, artist, thumb, duration)
                    if (collected.size >= limit) break
                }
                if (collected.size >= limit) break
            }
            if (collected.size >= limit) break
        }
        return mergeSongMaps(collected).take(limit)
    }

    private suspend fun searchSongItems(query: String, limit: Int = 200): List<SongItem> {
        val audioSongs = mutableListOf<SongItem>()
        val videoSongs = mutableListOf<SongItem>()

        fun collect(items: List<SongItem>) {
            val deduped = items.dedupeItems()
            audioSongs += deduped.filterNot { it.isVideoSong }
            videoSongs += deduped.filter { it.isVideoSong }
        }

        for (variant in queryVariants(query)) {
            runCatching {
                YouTube.search(variant, YouTube.SearchFilter.FILTER_SONG)
                    .getOrThrow()
                    .items
                    .filterIsInstance<SongItem>()
            }.getOrDefault(emptyList()).let(::collect)

            runCatching {
                YouTube.searchSummary(variant).getOrThrow().summaries
                    .flatMap { it.items }
                    .filterIsInstance<SongItem>()
            }.getOrDefault(emptyList()).let(::collect)

            if (audioSongs.dedupeItems().size >= limit) break
        }

        if (audioSongs.dedupeItems().size < 24) {
            for (variant in expandedSongQueries(query).drop(queryVariants(query).size)) {
                runCatching {
                    YouTube.search(variant, YouTube.SearchFilter.FILTER_SONG)
                        .getOrThrow()
                        .items
                        .filterIsInstance<SongItem>()
                }.getOrDefault(emptyList()).let(::collect)
                if (audioSongs.dedupeItems().size >= 48) break
            }
        }

        if (audioSongs.dedupeItems().size < 18) {
            for (variant in queryVariants(query)) {
                runCatching {
                    YouTube.search(variant, YouTube.SearchFilter.FILTER_VIDEO)
                        .getOrThrow()
                        .items
                        .filterIsInstance<SongItem>()
                }.getOrDefault(emptyList()).let(::collect)
                if ((audioSongs + videoSongs).dedupeItems().size >= limit) break
            }
        }

        val audio = audioSongs.dedupeItems()
        val videos = videoSongs.dedupeItems().filterNot { video -> audio.any { it.id == video.id } }
        return (audio + videos).take(limit)
    }

    private suspend fun searchAlbumItems(query: String, limit: Int = 120): List<AlbumItem> {
        val all = mutableListOf<AlbumItem>()
        for (variant in queryVariants(query)) {
            runCatching {
                YouTube.searchSummary(variant).getOrThrow().summaries
                    .flatMap { it.items }
                    .filterIsInstance<AlbumItem>()
            }.getOrDefault(emptyList()).let { all += it }
            runCatching {
                YouTube.search(variant, YouTube.SearchFilter.FILTER_ALBUM)
                    .getOrThrow()
                    .items
                    .filterIsInstance<AlbumItem>()
            }.getOrDefault(emptyList()).let { all += it }
            if (all.size >= limit) break
        }
        return all.dedupeItems().take(limit)
    }

    private suspend fun searchArtistItems(query: String, limit: Int = 120): List<ArtistItem> {
        val all = mutableListOf<ArtistItem>()
        for (variant in queryVariants(query)) {
            runCatching {
                YouTube.searchSummary(variant).getOrThrow().summaries
                    .flatMap { it.items }
                    .filterIsInstance<ArtistItem>()
            }.getOrDefault(emptyList()).let { all += it }
            runCatching {
                YouTube.search(variant, YouTube.SearchFilter.FILTER_ARTIST)
                    .getOrThrow()
                    .items
                    .filterIsInstance<ArtistItem>()
            }.getOrDefault(emptyList()).let { all += it }
            if (all.size >= limit) break
        }
        return all.dedupeItems().take(limit)
    }

    private suspend fun searchPlaylistItems(query: String, limit: Int = 120): List<PlaylistItem> {
        val all = mutableListOf<PlaylistItem>()
        for (variant in queryVariants(query)) {
            runCatching {
                YouTube.searchSummary(variant).getOrThrow().summaries
                    .flatMap { it.items }
                    .mapNotNull {
                        when (it) {
                            is PlaylistItem -> it
                            is PodcastItem -> it.asPlaylistItem()
                            else -> null
                        }
                    }
            }.getOrDefault(emptyList()).let { all += it }
            runCatching {
                YouTube.search(variant, YouTube.SearchFilter.FILTER_FEATURED_PLAYLIST)
                    .getOrThrow()
                    .items
                    .filterIsInstance<PlaylistItem>()
            }.getOrDefault(emptyList()).let { all += it }
            runCatching {
                YouTube.search(variant, YouTube.SearchFilter.FILTER_COMMUNITY_PLAYLIST)
                    .getOrThrow()
                    .items
                    .filterIsInstance<PlaylistItem>()
            }.getOrDefault(emptyList()).let { all += it }
            if (all.size >= limit) break
        }
        return all.dedupeItems().take(limit)
    }

    fun search(context: Context, query: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return@runBlocking home(context)

        val nativeSongMaps = searchSongItems(trimmed).take(200).map { songMap(it) }
        val fallbackSongMaps = if (nativeSongMaps.size < 40) fetchYoutubeWebSongMaps(trimmed, page = 0, limit = 80) else emptyList()
        val albumItems = searchAlbumItems(trimmed)
        val artistItems = searchArtistItems(trimmed)
        val playlistItems = searchPlaylistItems(trimmed)

        mapOf(
            "songs" to mergeSongMaps(nativeSongMaps + fallbackSongMaps).take(220),
            "albums" to albumItems.take(100).map { albumMap(it) },
            "artists" to artistItems.take(100).map { artistMap(it) },
            "playlists" to playlistItems.take(100).map { playlistMap(it) },
        )
    }

    fun searchSongs(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val trimmed = query.trim()
        val native = searchSongItems(trimmed).map { songMap(it) }
        val fallback = if (native.size < 60) fetchYoutubeWebSongMaps(trimmed, page = 0, limit = 100) else emptyList()
        mergeSongMaps(native + fallback).take(220)
    }

    fun searchSongsPage(context: Context, query: String, continuation: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val token = continuation.trim()
        val trimmed = query.trim()

        fun resultMap(nativeItems: List<SongItem>, fallbackMaps: List<Map<String, Any?>>, next: String?): Map<String, Any?> {
            val nativeMaps = nativeItems.dedupeItems().map { songMap(it) }
            return mapOf(
                "items" to mergeSongMaps(nativeMaps + fallbackMaps).take(80),
                "continuation" to (next ?: ""),
            )
        }

        val synthetic = parseSyntheticContinuation(token)
        if (synthetic != null) {
            val (syntheticQuery, pageIndex) = synthetic
            val queries = expandedSongQueries(syntheticQuery)
            val startIndex = ((pageIndex - 1) * 2).coerceAtLeast(0)
            val selectedQueries = queries.drop(startIndex).take(2).ifEmpty { queryVariants(syntheticQuery).take(1) }
            val collected = mutableListOf<SongItem>()
            for (variant in selectedQueries) {
                runCatching { YouTube.search(variant, YouTube.SearchFilter.FILTER_SONG).getOrThrow().items.filterIsInstance<SongItem>() }
                    .getOrDefault(emptyList()).let { collected += it }
                runCatching { YouTube.searchSummary(variant).getOrThrow().summaries.flatMap { it.items }.filterIsInstance<SongItem>() }
                    .getOrDefault(emptyList()).let { collected += it }
            }
            if (collected.dedupeItems().size < 25) {
                for (variant in selectedQueries) {
                    runCatching { YouTube.search(variant, YouTube.SearchFilter.FILTER_VIDEO).getOrThrow().items.filterIsInstance<SongItem>() }
                        .getOrDefault(emptyList()).let { collected += it }
                }
            }
            val fallback = fetchYoutubeWebSongMaps(syntheticQuery, page = pageIndex, limit = 80)
            val hasMoreSynthetic = pageIndex < 12 && (startIndex + 2 < queries.size || fallback.isNotEmpty())
            return@runBlocking resultMap(
                collected.dedupeItems(),
                fallback,
                if (hasMoreSynthetic) syntheticContinuation(syntheticQuery, pageIndex + 1) else null,
            )
        }

        if (trimmed.isBlank()) return@runBlocking resultMap(emptyList(), emptyList(), null)

        // Most important path for the UI: return something immediately after the user presses
        // the keyboard search button. The Innertube filtered music search can return empty or
        // stall on some devices/accounts, so use the public YouTube result page first as a
        // safety net. Playback still uses the Metrolist/YTPlayerUtils pipeline by videoId.
        val immediateFallback = fetchYoutubeWebSongMaps(trimmed, page = 0, limit = 80)
        if (immediateFallback.isNotEmpty()) {
            return@runBlocking resultMap(emptyList(), immediateFallback, syntheticContinuation(trimmed, 1))
        }

        val collected = mutableListOf<SongItem>()
        var continuationOut: String? = null

        if (token.isNotBlank()) {
            val page = runCatching { YouTube.searchContinuation(token).getOrThrow() }.getOrNull()
            if (page != null) {
                collected += page.items.filterIsInstance<SongItem>()
                continuationOut = page.continuation
            }
            val fallback = if (collected.dedupeItems().size < 50) fetchYoutubeWebSongMaps(trimmed, page = 1, limit = 80) else emptyList()
            val next = continuationOut?.takeIf { it.isNotBlank() } ?: syntheticContinuation(trimmed, 2)
            return@runBlocking resultMap(collected.dedupeItems(), fallback, next)
        }

        for (variant in queryVariants(trimmed)) {
            val page = runCatching { YouTube.search(variant, YouTube.SearchFilter.FILTER_SONG).getOrThrow() }.getOrNull()
            if (page != null) {
                if (continuationOut.isNullOrBlank()) continuationOut = page.continuation
                collected += page.items.filterIsInstance<SongItem>()
            }
            runCatching { YouTube.searchSummary(variant).getOrThrow().summaries.flatMap { it.items }.filterIsInstance<SongItem>() }
                .getOrDefault(emptyList()).let { collected += it }
            if (collected.filterNot { it.isVideoSong }.dedupeItems().size >= 50) break
        }
        if (collected.filterNot { it.isVideoSong }.dedupeItems().size < 30) {
            for (variant in expandedSongQueries(trimmed).drop(queryVariants(trimmed).size)) {
                val page = runCatching { YouTube.search(variant, YouTube.SearchFilter.FILTER_SONG).getOrThrow() }.getOrNull()
                if (page != null) {
                    if (continuationOut.isNullOrBlank()) continuationOut = page.continuation
                    collected += page.items.filterIsInstance<SongItem>()
                }
                if (collected.filterNot { it.isVideoSong }.dedupeItems().size >= 70) break
            }
        }
        if (collected.dedupeItems().size < 20) {
            for (variant in queryVariants(trimmed)) {
                val page = runCatching { YouTube.search(variant, YouTube.SearchFilter.FILTER_VIDEO).getOrThrow() }.getOrNull()
                if (page != null) {
                    if (continuationOut.isNullOrBlank()) continuationOut = page.continuation
                    collected += page.items.filterIsInstance<SongItem>()
                }
            }
        }
        val fallback = if (collected.dedupeItems().size < 80) fetchYoutubeWebSongMaps(trimmed, page = 0, limit = 100) else emptyList()
        val next = continuationOut?.takeIf { it.isNotBlank() } ?: syntheticContinuation(trimmed, 1)
        resultMap(collected.dedupeItems(), fallback, next)
    }

    fun searchAlbums(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        searchAlbumItems(query.trim()).map { albumMap(it) }
    }

    fun searchArtists(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        searchArtistItems(query.trim()).map { artistMap(it) }
    }

    fun searchPlaylists(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        searchPlaylistItems(query.trim()).map { playlistMap(it) }
    }

    fun fetchPersonalizedPlaylists(context: Context, queries: List<String>): List<Map<String, Any?>> {
        ensureInitialized(context)
        val seeds = if (queries.isEmpty()) {
            listOf("hits brasil playlist", "top musicas brasil playlist", "pop brasil playlist", "kpop hits playlist")
        } else {
            queries.map { "$it playlist" }
        }
        val all = mutableListOf<Map<String, Any?>>()
        for (query in seeds.take(8)) {
            runCatching { all += searchPlaylists(context, query).take(12) }
        }
        return all.distinctBy { (it["playlistId"] ?: it["browseId"] ?: it["title"]).toString() }.take(60)
    }


    fun lyrics(context: Context, title: String, artist: String, album: String, durationMs: Int): String {
        ensureInitialized(context)
        val cleanTitle = title.cleanLyricQuery()
        val cleanArtist = artist.cleanLyricQuery()
        val cleanAlbum = album.cleanLyricQuery()
        if (cleanTitle.isBlank() || cleanArtist.isBlank()) return ""

        fun get(url: String): String? = runCatching {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Metrolist/Flutter Music App")
                .header("Accept", "application/json")
                .get()
                .build()
            quickHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) null else response.body?.string()
            }
        }.getOrNull()

        val durationSeconds = (durationMs / 1000).takeIf { it > 0 }
        val exactUrl = buildString {
            append("https://lrclib.net/api/get?track_name=").append(enc(cleanTitle))
            append("&artist_name=").append(enc(cleanArtist))
            if (cleanAlbum.isNotBlank() && cleanAlbum != "YouTube Music") append("&album_name=").append(enc(cleanAlbum))
            durationSeconds?.let { append("&duration=").append(it) }
        }
        get(exactUrl)?.let { body ->
            runCatching { parseLyricsObject(JSONObject(body)) }.getOrNull()?.let { return it }
        }

        val searchUrl = "https://lrclib.net/api/search?q=${enc(listOf(cleanTitle, cleanArtist).joinToString(" "))}"
        get(searchUrl)?.let { body ->
            val array = runCatching { JSONArray(body) }.getOrNull() ?: return@let
            var best: JSONObject? = null
            var bestScore = Int.MIN_VALUE
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val trackName = item.optString("trackName", "").lowercase()
                val artistName = item.optString("artistName", "").lowercase()
                var score = 0
                if (trackName == cleanTitle.lowercase()) score += 100 else if (trackName.contains(cleanTitle.lowercase())) score += 40
                if (artistName.contains(cleanArtist.lowercase())) score += 60
                durationSeconds?.let { d ->
                    val remoteDuration = item.optInt("duration", 0)
                    if (remoteDuration > 0) score -= kotlin.math.abs(remoteDuration - d)
                }
                if (score > bestScore) {
                    bestScore = score
                    best = item
                }
            }
            best?.let { parseLyricsObject(it)?.let { lyrics -> return lyrics } }
        }
        return ""
    }

    private fun parseLyricsObject(item: JSONObject): String? {
        val synced = item.optString("syncedLyrics", "").trim()
        if (synced.isNotEmpty() && synced.lowercase() != "null") return synced
        val plain = item.optString("plainLyrics", "").trim()
        if (plain.isNotEmpty() && plain.lowercase() != "null") return plain
        return null
    }

    private fun enc(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8.name())

    private fun String.cleanLyricQuery(): String = trim()
        .replace(Regex("\\s+"), " ")
        .replace(Regex("\\s*[-–—]\\s*(official|audio|video|lyrics?|mv|m/v|visualizer).*$", RegexOption.IGNORE_CASE), "")
        .replace(Regex("\\((official|audio|video|lyrics?|mv|m/v|visualizer)[^)]*\\)", RegexOption.IGNORE_CASE), "")
        .trim()

    fun album(context: Context, browseId: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val page = YouTube.album(browseId.trim()).getOrThrow()
        val albumArtist = page.album.artists?.joinToString(" ") { it.name }.orEmpty()
        val directSongs = page.songs.dedupeItems()
        val albumSongs = if (directSongs.isNotEmpty()) {
            directSongs
        } else {
            runCatching {
                YouTube.albumSongs(page.album.playlistId.removePrefix("VL"), page.album).getOrThrow()
            }.getOrDefault(emptyList()).dedupeItems()
        }
        val playlistSongs = if (albumSongs.isNotEmpty()) {
            albumSongs
        } else {
            runCatching {
                YouTube.playlist(page.album.playlistId.removePrefix("VL")).getOrThrow().songs
            }.getOrDefault(emptyList()).dedupeItems()
        }
        val fallbackSongs = if (playlistSongs.isNotEmpty()) {
            playlistSongs
        } else {
            // Last-resort fallback for YouTube Music album pages that expose the
            // header but no shelf in the regional response. Keep audio tracks
            // first and bias the query with artist + album title.
            searchSongItems(listOf(albumArtist, page.album.title).filter { it.isNotBlank() }.joinToString(" "), limit = 80)
        }
        mapOf(
            "album" to albumMap(page.album),
            "tracks" to fallbackSongs.dedupeItems().map { songMap(it) },
        )
    }

    fun artist(context: Context, browseId: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val page = YouTube.artist(browseId.trim()).getOrThrow()
        val allItems = page.sections.flatMap { it.items }
        val sectionSongs = allItems.filterIsInstance<SongItem>().dedupeItems()
        var topSongs = (sectionSongs.filterNot { it.isVideoSong } + sectionSongs.filter { it.isVideoSong }).dedupeItems().take(80)
        val albums = allItems.filterIsInstance<AlbumItem>().dedupeItems().take(80)
        val playlists = allItems.filterIsInstance<PlaylistItem>().dedupeItems().take(60)
        val songSection = page.sections.firstOrNull { section -> section.items.any { it is SongItem } }
        val albumSection = page.sections.firstOrNull { section -> section.items.any { it is AlbumItem } }

        // Some artist pages only expose albums/playlists in the first payload.
        // Metrolist's UI can still play/search songs, so fallback to a real
        // artist song search instead of showing “Nenhuma música encontrada”.
        if (topSongs.isEmpty() && page.artist.title.isNotBlank()) {
            topSongs = searchSongItems(page.artist.title, limit = 80)
        }

        mapOf(
            "artist" to artistMap(page.artist),
            "topSongs" to topSongs.map { songMap(it) },
            "albums" to albums.map { albumMap(it) },
            "playlists" to playlists.map { playlistMap(it) },
            "songsMoreBrowseId" to songSection?.moreEndpoint?.browseId,
            "songsMoreParams" to songSection?.moreEndpoint?.params,
            "albumsMoreBrowseId" to albumSection?.moreEndpoint?.browseId,
            "albumsMoreParams" to albumSection?.moreEndpoint?.params,
        )
    }

    fun artistSongs(context: Context, artistName: String, artistBrowseId: String, moreBrowseId: String?, moreParams: String?): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val endpointId = moreBrowseId?.trim().orEmpty()
        val endpointSongsRaw = if (endpointId.isNotEmpty()) {
            runCatching {
                YouTube.artistItems(BrowseEndpoint(endpointId, moreParams?.takeIf { it.isNotBlank() }))
                    .getOrThrow()
                    .items
                    .filterIsInstance<SongItem>()
            }.getOrDefault(emptyList())
        } else {
            emptyList()
        }
        val endpointSongs = (endpointSongsRaw.filterNot { it.isVideoSong } + endpointSongsRaw.filter { it.isVideoSong }).dedupeItems()
        val fallbackSongs = if (endpointSongs.isEmpty()) searchSongItems(artistName.trim(), limit = 200) else emptyList()
        (endpointSongs + fallbackSongs).dedupeItems().take(200).map { songMap(it) }
    }

    fun artistAlbums(context: Context, artistName: String, artistBrowseId: String, moreBrowseId: String?, moreParams: String?): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val endpointId = moreBrowseId?.trim().orEmpty()
        val endpointAlbums = if (endpointId.isNotEmpty()) {
            runCatching {
                YouTube.artistItems(BrowseEndpoint(endpointId, moreParams?.takeIf { it.isNotBlank() }))
                    .getOrThrow()
                    .items
                    .filterIsInstance<AlbumItem>()
            }.getOrDefault(emptyList())
        } else {
            emptyList()
        }
        val fallbackAlbums = if (endpointAlbums.isEmpty()) searchAlbumItems(artistName.trim(), limit = 120) else emptyList()
        (endpointAlbums + fallbackAlbums).dedupeItems().take(120).map { albumMap(it) }
    }

    fun playlist(context: Context, playlistId: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val id = playlistId.trim().removePrefix("VL")
        val page = YouTube.playlist(id).getOrThrow()
        mapOf(
            "playlist" to playlistMap(page.playlist),
            "tracks" to page.songs.dedupeItems().map { songMap(it) },
        )
    }

    private fun searchResultMap(items: List<YTItem>): Map<String, Any?> {
        val songs = items.filterIsInstance<SongItem>().filterVideoSongs(false).dedupeItems().take(120).map { songMap(it) }
        val albums = items.filterIsInstance<AlbumItem>().dedupeItems().take(60).map { albumMap(it) }
        val artists = items.filterIsInstance<ArtistItem>().dedupeItems().take(60).map { artistMap(it) }
        val playlists = items.mapNotNull {
            when (it) {
                is PlaylistItem -> it
                is PodcastItem -> it.asPlaylistItem()
                else -> null
            }
        }.dedupeItems().take(60).map { playlistMap(it) }
        return mapOf(
            "songs" to songs,
            "albums" to albums,
            "artists" to artists,
            "playlists" to playlists,
        )
    }

    private fun highQualityThumbnail(raw: String?): String {
        val url = raw?.trim().orEmpty()
        if (url.isEmpty()) return ""
        val upgraded = url.replace(Regex("=w\\d+-h\\d+(?:-[^?&]*)?"), "=w544-h544-l90-rj")
        return upgraded
            .replace("=s60", "=s544")
            .replace("=s120", "=s544")
            .replace("=s226", "=s544")
            .replace("hqdefault.jpg", "maxresdefault.jpg")
            .replace("mqdefault.jpg", "maxresdefault.jpg")
    }

    private fun songMap(song: SongItem): Map<String, Any?> {
        val artistText = song.artists.joinToString(", ") { it.name }.ifBlank { "YouTube Music" }
        val artistId = song.artists.firstOrNull()?.id
        val albumName = song.album?.name ?: "YouTube Music"
        val durationMs = (song.duration ?: 0) * 1000
        return mapOf(
            "id" to song.id,
            "uri" to "",
            "title" to song.title,
            "artist" to artistText,
            "album" to albumName,
            "duration" to durationMs,
            "path" to "",
            "mimeType" to "audio/webm",
            "dateAdded" to 0,
            "dateModified" to 0,
            "artworkUrl" to highQualityThumbnail(song.thumbnail),
            "isRemote" to true,
            "remoteStreamUri" to "",
            "videoId" to song.id,
            "artistId" to artistId,
            "browseId" to song.album?.id,
            "trackNumber" to null,
        )
    }

    private fun albumMap(album: AlbumItem): Map<String, Any?> = mapOf(
        "browseId" to album.browseId,
        "id" to album.id,
        "playlistId" to album.playlistId,
        "title" to album.title,
        "artist" to album.artists?.joinToString(", ") { it.name }.orEmpty(),
        "thumbnailUrl" to highQualityThumbnail(album.thumbnail),
        "thumbnail" to highQualityThumbnail(album.thumbnail),
        "year" to album.year?.toString(),
    )

    private fun artistMap(artist: ArtistItem): Map<String, Any?> = mapOf(
        "browseId" to artist.id,
        "id" to artist.id,
        "name" to artist.title,
        "title" to artist.title,
        "thumbnailUrl" to highQualityThumbnail(artist.thumbnail),
        "thumbnail" to highQualityThumbnail(artist.thumbnail),
    )

    private fun playlistMap(playlist: PlaylistItem): Map<String, Any?> = mapOf(
        "playlistId" to playlist.id.removePrefix("VL"),
        "id" to playlist.id.removePrefix("VL"),
        "browseId" to "VL${playlist.id.removePrefix("VL")}",
        "title" to playlist.title,
        "author" to (playlist.author?.name ?: "YouTube Music"),
        "thumbnailUrl" to highQualityThumbnail(playlist.thumbnail),
        "thumbnail" to highQualityThumbnail(playlist.thumbnail),
        "songCountText" to playlist.songCountText,
    )

    private fun <T : YTItem> List<T>.dedupeItems(): List<T> = distinctBy { it.id }
}
