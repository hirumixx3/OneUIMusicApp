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
import kotlinx.coroutines.runBlocking
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import timber.log.Timber

/**
 * Online catalog bridge backed only by Metrolist's native Innertube module.
 * Dart no longer calls YouTube Music HTTP/json parsing.
 */
object MetrolistOnlineBridge {
    @Volatile private var initialized = false

    private fun ensureInitialized(context: Context) {
        if (!initialized) {
            synchronized(this) {
                if (!initialized) {
                    if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
                    CipherDeobfuscator.initialize(context.applicationContext)
                    initialized = true
                }
            }
        }
    }

    fun home(context: Context): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val collected = mutableListOf<YTItem>()
        runCatching {
            val page = YouTube.home().getOrThrow()
            collected += page.sections.flatMap { it.items }
        }
        val seeds = listOf(
            "new music",
            "top songs brasil",
            "kpop hits",
            "pop hits",
            "relax music",
            "playlist brasil",
        )
        for (seed in seeds) {
            if (collected.filterIsInstance<SongItem>().size >= 40 &&
                collected.filterIsInstance<PlaylistItem>().size >= 10 &&
                collected.filterIsInstance<ArtistItem>().size >= 10) break
            runCatching {
                val summary = YouTube.searchSummary(seed).getOrThrow()
                collected += summary.summaries.flatMap { it.items }
            }
        }
        searchResultMap(collected.dedupeItems())
    }

    fun search(context: Context, query: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return@runBlocking home(context)

        val summaryItems = runCatching {
            YouTube.searchSummary(trimmed).getOrThrow().summaries.flatMap { it.items }
        }.getOrDefault(emptyList())

        val songItems = runCatching {
            YouTube.search(trimmed, YouTube.SearchFilter.FILTER_SONG)
                .getOrThrow()
                .items
                .filterIsInstance<SongItem>()
                .filterVideoSongs(true)
        }.getOrDefault(emptyList())

        val albumItems = runCatching {
            YouTube.search(trimmed, YouTube.SearchFilter.FILTER_ALBUM)
                .getOrThrow()
                .items
                .filterIsInstance<AlbumItem>()
        }.getOrDefault(emptyList())

        val artistItems = runCatching {
            YouTube.search(trimmed, YouTube.SearchFilter.FILTER_ARTIST)
                .getOrThrow()
                .items
                .filterIsInstance<ArtistItem>()
        }.getOrDefault(emptyList())

        val playlistItems = runCatching {
            YouTube.search(trimmed, YouTube.SearchFilter.FILTER_FEATURED_PLAYLIST)
                .getOrThrow()
                .items
                .filterIsInstance<PlaylistItem>()
        }.getOrDefault(emptyList()) + runCatching {
            YouTube.search(trimmed, YouTube.SearchFilter.FILTER_COMMUNITY_PLAYLIST)
                .getOrThrow()
                .items
                .filterIsInstance<PlaylistItem>()
        }.getOrDefault(emptyList())

        val summarySongs = summaryItems.filterIsInstance<SongItem>().filterVideoSongs(true)
        val summaryAlbums = summaryItems.filterIsInstance<AlbumItem>()
        val summaryArtists = summaryItems.filterIsInstance<ArtistItem>()
        val summaryPlaylists = summaryItems.mapNotNull {
            when (it) {
                is PlaylistItem -> it
                is PodcastItem -> it.asPlaylistItem()
                else -> null
            }
        }

        mapOf(
            "songs" to (summarySongs + songItems).dedupeItems().take(200).map { songMap(it) },
            "albums" to (summaryAlbums + albumItems).dedupeItems().take(100).map { albumMap(it) },
            "artists" to (summaryArtists + artistItems).dedupeItems().take(100).map { artistMap(it) },
            "playlists" to (summaryPlaylists + playlistItems).dedupeItems().take(100).map { playlistMap(it) },
        )
    }

    fun searchSongs(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        YouTube.search(query.trim(), YouTube.SearchFilter.FILTER_SONG)
            .getOrThrow()
            .items
            .filterIsInstance<SongItem>()
            .filterVideoSongs(true)
            .dedupeItems()
            .map { songMap(it) }
    }

    fun searchAlbums(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        YouTube.search(query.trim(), YouTube.SearchFilter.FILTER_ALBUM)
            .getOrThrow()
            .items
            .filterIsInstance<AlbumItem>()
            .dedupeItems()
            .map { albumMap(it) }
    }

    fun searchArtists(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        YouTube.search(query.trim(), YouTube.SearchFilter.FILTER_ARTIST)
            .getOrThrow()
            .items
            .filterIsInstance<ArtistItem>()
            .dedupeItems()
            .map { artistMap(it) }
    }

    fun searchPlaylists(context: Context, query: String): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val featured = runCatching {
            YouTube.search(query.trim(), YouTube.SearchFilter.FILTER_FEATURED_PLAYLIST)
                .getOrThrow()
                .items
                .filterIsInstance<PlaylistItem>()
        }.getOrDefault(emptyList())
        val community = runCatching {
            YouTube.search(query.trim(), YouTube.SearchFilter.FILTER_COMMUNITY_PLAYLIST)
                .getOrThrow()
                .items
                .filterIsInstance<PlaylistItem>()
        }.getOrDefault(emptyList())
        (featured + community).dedupeItems().map { playlistMap(it) }
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
            MetrolistStreamResolver.httpClient.newCall(request).execute().use { response ->
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
        mapOf(
            "album" to albumMap(page.album),
            "tracks" to page.songs.dedupeItems().map { songMap(it) },
        )
    }

    fun artist(context: Context, browseId: String): Map<String, Any?> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val page = YouTube.artist(browseId.trim()).getOrThrow()
        val allItems = page.sections.flatMap { it.items }
        val topSongs = allItems.filterIsInstance<SongItem>().filterVideoSongs(true).dedupeItems().take(80)
        val albums = allItems.filterIsInstance<AlbumItem>().dedupeItems().take(80)
        val playlists = allItems.filterIsInstance<PlaylistItem>().dedupeItems().take(60)
        val songSection = page.sections.firstOrNull { section -> section.items.any { it is SongItem } }
        val albumSection = page.sections.firstOrNull { section -> section.items.any { it is AlbumItem } }
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
        val songs = if (endpointId.isNotEmpty()) {
            YouTube.artistItems(BrowseEndpoint(endpointId, moreParams?.takeIf { it.isNotBlank() }))
                .getOrThrow()
                .items
                .filterIsInstance<SongItem>()
                .filterVideoSongs(true)
        } else {
            YouTube.search(artistName.trim(), YouTube.SearchFilter.FILTER_SONG)
                .getOrThrow()
                .items
                .filterIsInstance<SongItem>()
                .filterVideoSongs(true)
        }
        songs.dedupeItems().take(200).map { songMap(it) }
    }

    fun artistAlbums(context: Context, artistName: String, artistBrowseId: String, moreBrowseId: String?, moreParams: String?): List<Map<String, Any?>> = runBlocking(Dispatchers.IO) {
        ensureInitialized(context)
        val endpointId = moreBrowseId?.trim().orEmpty()
        val albums = if (endpointId.isNotEmpty()) {
            YouTube.artistItems(BrowseEndpoint(endpointId, moreParams?.takeIf { it.isNotBlank() }))
                .getOrThrow()
                .items
                .filterIsInstance<AlbumItem>()
        } else {
            YouTube.search(artistName.trim(), YouTube.SearchFilter.FILTER_ALBUM)
                .getOrThrow()
                .items
                .filterIsInstance<AlbumItem>()
        }
        albums.dedupeItems().take(120).map { albumMap(it) }
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
        val songs = items.filterIsInstance<SongItem>().filterVideoSongs(true).dedupeItems().take(120).map { songMap(it) }
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
