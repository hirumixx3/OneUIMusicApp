package com.hirumisu.musicapp

import android.content.ContentUris
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.Charset
import java.text.Normalizer
import kotlin.math.min

object FastAudioScanner {
    fun scan(context: Context): String {
        val resolver = context.contentResolver
        val out = JSONArray()
        val seen = linkedSetOf<String>()

        val volumes = linkedSetOf<String>().apply {
            add(MediaStore.VOLUME_EXTERNAL)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                addAll(MediaStore.getExternalVolumeNames(context))
            }
        }

        for (volume in volumes) {
            val uri = MediaStore.Audio.Media.getContentUri(volume)
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.ALBUM_ID,
                MediaStore.Audio.Media.ALBUM_ARTIST,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.MIME_TYPE,
                MediaStore.Audio.Media.YEAR,
                MediaStore.Audio.Media.TRACK,
                MediaStore.Audio.Media.IS_MUSIC,
                MediaStore.Audio.Media.DATA
            )

            try {
                resolver.query(
                    uri,
                    projection,
                    "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 0",
                    null,
                    "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
                )?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                    val titleCol = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
                    val displayCol = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                    val artistCol = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
                    val albumCol = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
                    val albumIdCol = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
                    val albumArtistCol = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM_ARTIST)
                    val durationCol = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
                    val dateAddedCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_ADDED)
                    val dateModifiedCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
                    val mimeCol = cursor.getColumnIndex(MediaStore.Audio.Media.MIME_TYPE)
                    val yearCol = cursor.getColumnIndex(MediaStore.Audio.Media.YEAR)
                    val trackCol = cursor.getColumnIndex(MediaStore.Audio.Media.TRACK)
                    val dataCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)

                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(idCol)
                        val contentUri = ContentUris.withAppendedId(uri, id).toString()
                        val path = readString(cursor, dataCol)
                        val title = readString(cursor, titleCol).ifBlank { readString(cursor, displayCol) }
                        val artist = readString(cursor, artistCol).ifBlank { "Desconhecido" }
                        val album = readString(cursor, albumCol).ifBlank { "Desconhecido" }
                        val albumId = readLong(cursor, albumIdCol)
                        val duration = readLong(cursor, durationCol)
                        val mediaStoreYear = readInt(cursor, yearCol)
                        val resolvedYear = if (mediaStoreYear > 0) mediaStoreYear else 0
                        val lyrics = ""

                        val dedupeKey = when {
                            path.isNotBlank() -> path.lowercase()
                            else -> "${title.lowercase()}|${artist.lowercase()}|${album.lowercase()}|$duration"
                        }
                        if (!seen.add(dedupeKey)) continue

                        val item = JSONObject()
                        item.put("id", id)
                        item.put("uri", contentUri)
                        item.put("title", title)
                        item.put("displayName", readString(cursor, displayCol))
                        item.put("artist", artist)
                        item.put("album", album)
                        item.put("albumId", albumId)
                        item.put("duration", duration)
                        item.put("dateAdded", readLong(cursor, dateAddedCol))
                        item.put("dateModified", readLong(cursor, dateModifiedCol))
                        item.put("mimeType", readString(cursor, mimeCol))
                        item.put("path", path)
                        item.put("year", resolvedYear)
                        item.put("trackNumber", readInt(cursor, trackCol))
                        item.put("composer", "")
                        item.put("albumArtist", readString(cursor, albumArtistCol))
                        item.put("genre", "")
                        item.put("author", "")
                        item.put("writer", "")
                        item.put("discNumber", "")
                        item.put("bitrate", "")
                        item.put("lyrics", lyrics)
                        out.put(item)
                    }
                }
            } catch (_: Exception) {
                // Continua escaneando outros volumes sem travar a UI.
            }
        }

        return out.toString()
    }

    fun scanToCacheFile(context: Context): String {
        val file = File(context.cacheDir, "audio_scan.json")
        file.writeText(scan(context))
        return file.absolutePath
    }

    fun readArtworkBase64(context: Context, uri: String, albumIdRaw: String, path: String): String? {
        val albumId = albumIdRaw.toLongOrNull() ?: 0L

        if (albumId > 0) {
            try {
                val albumArtUri = Uri.parse("content://media/external/audio/albumart/$albumId")
                context.contentResolver.openInputStream(albumArtUri)?.use { input ->
                    val bytes = input.readBytes()
                    if (bytes.isNotEmpty()) {
                        return Base64.encodeToString(bytes, Base64.NO_WRAP)
                    }
                }
            } catch (_: Exception) {
            }
        }

        if (uri.isNotBlank()) {
            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(context, Uri.parse(uri))
                val bytes = retriever.embeddedPicture
                retriever.release()
                if (bytes != null && bytes.isNotEmpty()) {
                    return Base64.encodeToString(bytes, Base64.NO_WRAP)
                }
            } catch (_: Exception) {
            }
        }

        if (path.isNotBlank()) {
            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(path)
                val bytes = retriever.embeddedPicture
                retriever.release()
                if (bytes != null && bytes.isNotEmpty()) {
                    return Base64.encodeToString(bytes, Base64.NO_WRAP)
                }
            } catch (_: Exception) {
            }
        }

        return null
    }

    private fun extractEmbeddedReleaseYear(context: Context, uri: String, path: String): Int {
        fun parseYear(raw: String?): Int {
            if (raw.isNullOrBlank()) return 0
            val match = Regex("""(19|20)\d{2}""").find(raw)
            return match?.value?.toIntOrNull() ?: 0
        }

        fun readWithRetriever(block: (MediaMetadataRetriever) -> Unit): Int {
            return try {
                val retriever = MediaMetadataRetriever()
                try {
                    block(retriever)
                    val fromYear = parseYear(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR))
                    if (fromYear > 0) return fromYear
                    val fromDate = parseYear(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE))
                    if (fromDate > 0) return fromDate
                    0
                } finally {
                    retriever.release()
                }
            } catch (_: Exception) {
                0
            }
        }

        if (uri.isNotBlank()) {
            val fromUri = readWithRetriever { it.setDataSource(context, Uri.parse(uri)) }
            if (fromUri > 0) return fromUri
        }

        if (path.isNotBlank()) {
            val fromPath = readWithRetriever { it.setDataSource(path) }
            if (fromPath > 0) return fromPath
        }

        return 0
    }

    private fun shouldAvoidDirectPath(path: String): Boolean {
        val normalized = path.trim().replace('\\', '/')
        if (normalized.isBlank()) return false
        if (normalized.startsWith("/storage/emulated/")) return false
        if (normalized.startsWith("/storage/self/primary/")) return false
        if (normalized.startsWith("/data/")) return false
        return Regex("^/storage/[^/]+/").containsMatchIn(normalized)
    }

    private fun canOpenDirectFile(file: File): Boolean {
        return try {
            if (!file.exists() || !file.isFile) return false
            FileInputStream(file).use { input ->
                val probe = ByteArray(1)
                input.read(probe)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun ensurePlayableFilePath(
        context: Context,
        id: String,
        uri: String,
        path: String,
        mimeType: String,
        title: String,
    ): String? {
        val directPath = path.trim()
        val directFile = if (directPath.isNotEmpty()) File(directPath) else null
        if (directFile != null && !shouldAvoidDirectPath(directPath) && canOpenDirectFile(directFile)) {
            return directFile.absolutePath
        }

        val parsedUri = uri.trim().takeIf { it.isNotBlank() }?.let { Uri.parse(it) }
        if (parsedUri?.scheme == "file") {
            val file = File(parsedUri.path ?: "")
            if (canOpenDirectFile(file)) {
                return file.absolutePath
            }
        }

        val resolvedDisplayName = parsedUri?.let { resolveDisplayName(context, it) } ?: ""
        val safeBaseName = sanitizeFileName(
            when {
                resolvedDisplayName.isNotBlank() -> File(resolvedDisplayName).nameWithoutExtension
                title.isNotBlank() -> title
                else -> id.ifBlank { "track" }
            }
        )
        val extension = guessExtension(directPath, mimeType, resolvedDisplayName)
        val outDir = File(context.cacheDir, "playable_audio").apply { mkdirs() }
        val outFile = File(outDir, "$safeBaseName-$id$extension")
        if (outFile.exists() && outFile.length() > 0L) {
            return outFile.absolutePath
        }

        if (parsedUri?.scheme == "content") {
            val contentUri = parsedUri
            context.contentResolver.openInputStream(contentUri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }
            if (outFile.exists() && outFile.length() > 0L) {
                return outFile.absolutePath
            }
        }

        if (directFile != null && canOpenDirectFile(directFile)) {
            FileInputStream(directFile).use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }
            if (outFile.exists() && outFile.length() > 0L) {
                return outFile.absolutePath
            }
            return directFile.absolutePath
        }

        return null
    }

    fun readLyricsOnDemand(context: Context, uri: String, path: String, title: String, artist: String, album: String): String {
        val safePath = path.trim()
        val safeTitle = title.trim()
        val safeArtist = artist.trim()
        val safeAlbum = album.trim()

        val embedded = readEmbeddedLyrics(context, uri = uri.trim(), path = safePath)
        if (embedded.isNotBlank()) return embedded.take(20000)

        val direct = readSidecarLyrics(
            path = safePath,
            title = safeTitle,
            artist = safeArtist,
            album = safeAlbum,
        )
        if (direct.isNotBlank()) return direct

        if (uri.isNotBlank()) {
            val resolved = resolvePathFromUri(context, uri)
            if (resolved.isNotBlank()) {
                val fromEmbeddedResolved = readEmbeddedLyrics(context, uri = "", path = resolved)
                if (fromEmbeddedResolved.isNotBlank()) return fromEmbeddedResolved.take(20000)

                val fromResolved = readSidecarLyrics(
                    path = resolved,
                    title = safeTitle,
                    artist = safeArtist,
                    album = safeAlbum,
                )
                if (fromResolved.isNotBlank()) return fromResolved
            }
        }

        return ""
    }


    private fun readEmbeddedLyrics(context: Context, uri: String, path: String): String {
        return try {
            if (path.isNotBlank()) {
                FileInputStream(File(path)).use { input ->
                    extractEmbeddedLyricsFromStream(input)
                }
            } else if (uri.isNotBlank()) {
                context.contentResolver.openInputStream(Uri.parse(uri))?.use { input ->
                    extractEmbeddedLyricsFromStream(input)
                } ?: ""
            } else {
                ""
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun extractEmbeddedLyricsFromStream(input: InputStream): String {
        val bytes = readBoundedBytes(input, 2 * 1024 * 1024)
        if (bytes.isEmpty()) return ""

        val fromId3 = parseId3Lyrics(bytes)
        if (fromId3.isNotBlank()) return normalizeLyrics(fromId3)

        val fromFlac = parseFlacLyrics(bytes)
        if (fromFlac.isNotBlank()) return normalizeLyrics(fromFlac)

        val fromMp4 = parseMp4Lyrics(bytes)
        if (fromMp4.isNotBlank()) return normalizeLyrics(fromMp4)

        return ""
    }

    private fun readBoundedBytes(input: InputStream, limit: Int): ByteArray {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val maxRead = min(chunk.size, limit - total)
            if (maxRead <= 0) break
            val read = input.read(chunk, 0, maxRead)
            if (read <= 0) break
            buffer.write(chunk, 0, read)
            total += read
        }
        return buffer.toByteArray()
    }

    private fun parseId3Lyrics(bytes: ByteArray): String {
        if (bytes.size < 10) return ""
        if (!(bytes[0] == 'I'.code.toByte() && bytes[1] == 'D'.code.toByte() && bytes[2] == '3'.code.toByte())) {
            return ""
        }

        val version = bytes[3].toInt() and 0xFF
        val flags = bytes[5].toInt() and 0xFF
        val tagSize = synchsafeToInt(bytes, 6)
        val totalTagSize = min(bytes.size, 10 + tagSize + if ((flags and 0x10) != 0) 10 else 0)
        if (totalTagSize <= 10) return ""

        val rawTag = bytes.copyOfRange(0, totalTagSize)
        val tagBytes = if ((flags and 0x80) != 0) unsynchronize(rawTag) else rawTag
        var offset = 10

        while (offset < tagBytes.size) {
            val headerSize = if (version == 2) 6 else 10
            if (offset + headerSize > tagBytes.size) break

            val frameId = if (version == 2) {
                String(tagBytes, offset, 3, Charsets.ISO_8859_1)
            } else {
                String(tagBytes, offset, 4, Charsets.ISO_8859_1)
            }
            if (frameId.all { it == '\u0000' }) break

            val frameSize = when (version) {
                2 -> readInt24(tagBytes, offset + 3)
                3 -> readInt32(tagBytes, offset + 4)
                4 -> synchsafeToInt(tagBytes, offset + 4)
                else -> 0
            }
            if (frameSize <= 0) break

            val dataOffset = offset + headerSize
            val dataEnd = min(tagBytes.size, dataOffset + frameSize)
            if (dataOffset >= dataEnd) break
            val payload = tagBytes.copyOfRange(dataOffset, dataEnd)

            when (frameId) {
                "USLT", "ULT" -> {
                    val text = decodeUslt(payload)
                    if (text.isNotBlank()) return text
                }
                "TXXX", "TXX" -> {
                    val pair = decodeTxxx(payload)
                    val description = pair.first.lowercase()
                    if (description.contains("lyric")) {
                        val text = pair.second
                        if (text.isNotBlank()) return text
                    }
                }
            }

            offset = dataEnd
        }
        return ""
    }

    private fun decodeUslt(payload: ByteArray): String {
        if (payload.size < 4) return ""
        val encoding = payload[0].toInt() and 0xFF
        val start = 4
        val descEnd = findTextTerminator(payload, start, encoding)
        val lyricsStart = skipTerminator(descEnd, payload.size, encoding)
        if (lyricsStart >= payload.size) return ""
        return decodeText(payload.copyOfRange(lyricsStart, payload.size), encoding).trim()
    }

    private fun decodeTxxx(payload: ByteArray): Pair<String, String> {
        if (payload.isEmpty()) return "" to ""
        val encoding = payload[0].toInt() and 0xFF
        val descStart = 1
        val descEnd = findTextTerminator(payload, descStart, encoding)
        val description = decodeText(payload.copyOfRange(descStart, descEnd.coerceAtMost(payload.size)), encoding).trim()
        val valueStart = skipTerminator(descEnd, payload.size, encoding)
        val value = if (valueStart < payload.size) decodeText(payload.copyOfRange(valueStart, payload.size), encoding).trim() else ""
        return description to value
    }

    private fun decodeText(bytes: ByteArray, encoding: Int): String {
        if (bytes.isEmpty()) return ""
        val charset = when (encoding) {
            0 -> Charsets.ISO_8859_1
            1 -> Charsets.UTF_16
            2 -> Charset.forName("UTF-16BE")
            3 -> Charsets.UTF_8
            else -> Charsets.UTF_8
        }
        return try {
            String(bytes, charset)
                .replace("\u0000", "")
                .trim()
        } catch (_: Exception) {
            ""
        }
    }

    private fun findTextTerminator(bytes: ByteArray, start: Int, encoding: Int): Int {
        if (encoding == 1 || encoding == 2) {
            var i = start
            while (i + 1 < bytes.size) {
                if (bytes[i] == 0.toByte() && bytes[i + 1] == 0.toByte()) return i
                i += 2
            }
            return bytes.size
        }
        var i = start
        while (i < bytes.size) {
            if (bytes[i] == 0.toByte()) return i
            i++
        }
        return bytes.size
    }

    private fun skipTerminator(pos: Int, size: Int, encoding: Int): Int {
        return min(size, pos + if (encoding == 1 || encoding == 2) 2 else 1)
    }

    private fun unsynchronize(bytes: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(bytes.size)
        var i = 0
        while (i < bytes.size) {
            val current = bytes[i]
            if (current == 0xFF.toByte() && i + 1 < bytes.size && bytes[i + 1] == 0.toByte()) {
                out.write(0xFF)
                i += 2
            } else {
                out.write(current.toInt())
                i++
            }
        }
        return out.toByteArray()
    }

    private fun parseFlacLyrics(bytes: ByteArray): String {
        if (bytes.size < 8) return ""
        if (!(bytes[0] == 'f'.code.toByte() && bytes[1] == 'L'.code.toByte() && bytes[2] == 'a'.code.toByte() && bytes[3] == 'C'.code.toByte())) {
            return ""
        }
        var offset = 4
        while (offset + 4 <= bytes.size) {
            val header = bytes[offset].toInt() and 0xFF
            val isLast = (header and 0x80) != 0
            val blockType = header and 0x7F
            val length = ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
                ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
                (bytes[offset + 3].toInt() and 0xFF)
            val dataStart = offset + 4
            val dataEnd = min(bytes.size, dataStart + length)
            if (dataEnd <= dataStart) break
            if (blockType == 4) {
                val found = parseVorbisCommentLyrics(bytes.copyOfRange(dataStart, dataEnd))
                if (found.isNotBlank()) return found
            }
            offset = dataEnd
            if (isLast) break
        }
        return ""
    }

    private fun parseVorbisCommentLyrics(block: ByteArray): String {
        return try {
            val buf = ByteBuffer.wrap(block).order(ByteOrder.LITTLE_ENDIAN)
            if (buf.remaining() < 4) return ""
            val vendorLen = buf.int
            if (vendorLen < 0 || buf.remaining() < vendorLen + 4) return ""
            buf.position(buf.position() + vendorLen)
            val count = buf.int
            repeat(count.coerceAtMost(500)) {
                if (buf.remaining() < 4) return@repeat
                val len = buf.int
                if (len <= 0 || buf.remaining() < len) return@repeat
                val entryBytes = ByteArray(len)
                buf.get(entryBytes)
                val entry = String(entryBytes, Charsets.UTF_8)
                val idx = entry.indexOf('=')
                if (idx > 0) {
                    val key = entry.substring(0, idx).trim().uppercase()
                    val value = entry.substring(idx + 1).trim()
                    if (value.isNotBlank() && (key == "LYRICS" || key == "UNSYNCEDLYRICS" || key == "UNSYNCED LYRICS")) {
                        return value
                    }
                }
            }
            ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun parseMp4Lyrics(bytes: ByteArray): String {
        return try {
            parseMp4LyricsInRange(bytes, 0, bytes.size, insideMeta = false)
        } catch (_: Exception) {
            ""
        }
    }

    private fun parseMp4LyricsInRange(bytes: ByteArray, start: Int, end: Int, insideMeta: Boolean): String {
        var offset = start
        while (offset + 8 <= end) {
            var atomSize = readUInt32(bytes, offset)
            if (atomSize == 0L) break
            val type = readType(bytes, offset + 4)
            var headerSize = 8
            if (atomSize == 1L) {
                if (offset + 16 > end) break
                atomSize = readUInt64(bytes, offset + 8)
                headerSize = 16
            }
            if (atomSize <= 0L) break
            val atomEnd = min(end, offset + atomSize.toInt())
            if (atomEnd <= offset + headerSize) break

            when (type) {
                "moov", "udta", "ilst" -> {
                    val found = parseMp4LyricsInRange(bytes, offset + headerSize, atomEnd, insideMeta = type == "meta" || insideMeta)
                    if (found.isNotBlank()) return found
                }
                "meta" -> {
                    val childStart = min(atomEnd, offset + headerSize + 4)
                    val found = parseMp4LyricsInRange(bytes, childStart, atomEnd, insideMeta = true)
                    if (found.isNotBlank()) return found
                }
                "©lyr" -> {
                    val found = parseMp4DataAtom(bytes, offset + headerSize, atomEnd)
                    if (found.isNotBlank()) return found
                }
                "----" -> {
                    val found = parseMp4FreeformLyrics(bytes, offset + headerSize, atomEnd)
                    if (found.isNotBlank()) return found
                }
            }
            offset = atomEnd
        }
        return ""
    }

    private fun parseMp4FreeformLyrics(bytes: ByteArray, start: Int, end: Int): String {
        var offset = start
        var name = ""
        var value = ""
        while (offset + 8 <= end) {
            val size = readUInt32(bytes, offset).toInt()
            if (size <= 8 || offset + size > end) break
            val type = readType(bytes, offset + 4)
            when (type) {
                "name" -> {
                    val dataStart = offset + 12
                    if (dataStart <= offset + size) {
                        name = String(bytes.copyOfRange(dataStart, offset + size), Charsets.UTF_8).trim()
                    }
                }
                "data" -> {
                    val dataStart = offset + 16
                    if (dataStart <= offset + size) {
                        value = String(bytes.copyOfRange(dataStart, offset + size), Charsets.UTF_8)
                            .replace("\u0000", "")
                            .trim()
                    }
                }
            }
            offset += size
        }
        return if (name.lowercase().contains("lyric") || name.lowercase().contains("lyrics")) value else ""
    }

    private fun parseMp4DataAtom(bytes: ByteArray, start: Int, end: Int): String {
        var offset = start
        while (offset + 8 <= end) {
            val size = readUInt32(bytes, offset).toInt()
            if (size <= 8 || offset + size > end) break
            val type = readType(bytes, offset + 4)
            if (type == "data") {
                val dataStart = offset + 16
                if (dataStart <= offset + size) {
                    return String(bytes.copyOfRange(dataStart, offset + size), Charsets.UTF_8)
                        .replace("\u0000", "")
                        .trim()
                }
            }
            offset += size
        }
        return ""
    }

    private fun readUInt32(bytes: ByteArray, offset: Int): Long {
        return ((bytes[offset].toLong() and 0xFF) shl 24) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 8) or
            (bytes[offset + 3].toLong() and 0xFF)
    }

    private fun readUInt64(bytes: ByteArray, offset: Int): Long {
        var value = 0L
        for (i in 0 until 8) {
            value = (value shl 8) or (bytes[offset + i].toLong() and 0xFF)
        }
        return value
    }

    private fun readType(bytes: ByteArray, offset: Int): String {
        return String(bytes, offset, 4, Charsets.ISO_8859_1)
    }

    private fun readInt24(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
            (bytes[offset + 2].toInt() and 0xFF)
    }

    private fun readInt32(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 24) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
            (bytes[offset + 3].toInt() and 0xFF)
    }

    private fun synchsafeToInt(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0x7F) shl 21) or
            ((bytes[offset + 1].toInt() and 0x7F) shl 14) or
            ((bytes[offset + 2].toInt() and 0x7F) shl 7) or
            (bytes[offset + 3].toInt() and 0x7F)
    }

    private fun readSidecarLyrics(path: String, title: String, artist: String, album: String): String {
        if (path.isBlank()) return ""
        return try {
            val audioFile = File(path)
            val parent = audioFile.parentFile ?: return ""
            val baseName = audioFile.nameWithoutExtension
            val displayTitle = title
                .replace(Regex("""[\/:*?"<>|]"""), " ")
                .replace(Regex("""\s+"""), " ")
                .trim()
            val displayArtist = artist
                .replace(Regex("""[\/:*?"<>|]"""), " ")
                .replace(Regex("""\s+"""), " ")
                .trim()
            val displayAlbum = album
                .replace(Regex("""[\/:*?"<>|]"""), " ")
                .replace(Regex("""\s+"""), " ")
                .trim()

            val baseCandidates = linkedSetOf<String>().apply {
                add(baseName)
                add(baseName.substringBeforeLast(" - ", baseName))
                add(baseName.substringAfterLast("-", baseName).trim())
                add(baseName.substringBeforeLast("_", baseName))
                add(displayTitle)
                add(displayTitle.substringBeforeLast(" - ", displayTitle))
                add(displayTitle.substringAfterLast("-", displayTitle).trim())
                if (displayArtist.isNotBlank() && displayTitle.isNotBlank()) {
                    add("$displayArtist - $displayTitle")
                    add("$displayTitle - $displayArtist")
                    add("$displayArtist $displayTitle")
                    add("$displayTitle $displayArtist")
                }
                if (displayAlbum.isNotBlank() && displayTitle.isNotBlank()) {
                    add("$displayAlbum - $displayTitle")
                    add("$displayTitle - $displayAlbum")
                }
            }.map { sanitizeLyricsStem(it) }.filter { it.isNotBlank() }.distinct()

            val searchDirs = linkedSetOf<File>().apply {
                add(parent)
                add(File(parent, "Lyrics"))
                add(File(parent, "lyrics"))
                add(File(parent, "Letras"))
                add(File(parent, "letras"))
                parent.parentFile?.let {
                    add(File(it, "Lyrics"))
                    add(File(it, "lyrics"))
                    add(File(it, "Letras"))
                    add(File(it, "letras"))
                }
            }.filter { it.exists() && it.isDirectory }

            val exactCandidates = mutableListOf<File>()
            for (dir in searchDirs) {
                for (stem in baseCandidates) {
                    exactCandidates += File(dir, "$stem.lrc")
                    exactCandidates += File(dir, "$stem.txt")
                    exactCandidates += File(dir, "$stem.LRC")
                    exactCandidates += File(dir, "$stem.TXT")
                }
            }

            for (candidate in exactCandidates.distinct()) {
                if (candidate.exists() && candidate.isFile && candidate.length() in 1..1_000_000) {
                    return normalizeLyrics(candidate.readText()).take(12000)
                }
            }

            val wanted = baseCandidates.map { normalizeForMatch(it) }.filter { it.length >= 3 }
            for (dir in searchDirs) {
                val files = dir.listFiles()?.filter {
                    it.isFile && it.length() in 1..1_000_000 && (
                        it.extension.equals("lrc", ignoreCase = true) ||
                        it.extension.equals("txt", ignoreCase = true)
                    )
                } ?: emptyList()

                for (file in files) {
                    val normalizedFile = normalizeForMatch(file.nameWithoutExtension)
                    val matches = wanted.any { target ->
                        normalizedFile == target ||
                        normalizedFile.contains(target) ||
                        target.contains(normalizedFile)
                    }
                    if (matches) {
                        return normalizeLyrics(file.readText()).take(12000)
                    }
                }
            }
            ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun resolvePathFromUri(context: Context, rawUri: String): String {
        return try {
            val parsed = Uri.parse(rawUri)
            if (parsed.scheme == "file") {
                return parsed.path ?: ""
            }
            if (parsed.scheme != "content") return ""
            context.contentResolver.query(
                parsed,
                arrayOf(MediaStore.MediaColumns.DATA),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (index >= 0 && !cursor.isNull(index)) {
                        return cursor.getString(index) ?: ""
                    }
                }
            }
            ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun sanitizeLyricsStem(raw: String): String {
        return raw
            .replace(Regex("""[\/:*?"<>|]"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()
    }

    private fun normalizeLyrics(raw: String): String {
        return raw
            .replace(Regex("\\[(\\d{1,2}:)?\\d{1,2}(\\.\\d{1,2})?]"), "")
            .replace("\r", "")
            .lines()
            .map { it.trimEnd() }
            .joinToString("\n")
            .replace(Regex("\n{3,}"), "\n\n")
            .trim()
    }

    private fun normalizeForMatch(raw: String): String {
        return Normalizer.normalize(raw.lowercase(), Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "")
            .replace(Regex("""[\[\](){}]"""), " ")
            .replace(Regex("""feat\.?|ft\.?|featuring"""), " ")
            .replace(Regex("""[^a-z0-9]+"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()
    }

    private fun sanitizeFileName(raw: String): String {
        val safe = raw.replace(Regex("[^a-zA-Z0-9._-]"), "_").trim('_')
        return if (safe.isBlank()) "track" else safe.take(40)
    }

    private fun guessExtension(path: String, mimeType: String, displayName: String): String {
        val fromPath = path.substringAfterLast('.', "")
        if (fromPath.isNotBlank() && fromPath.length <= 5) {
            return ".${fromPath.lowercase()}"
        }

        val fromDisplayName = displayName.substringAfterLast('.', "")
        if (fromDisplayName.isNotBlank() && fromDisplayName.length <= 5) {
            return ".${fromDisplayName.lowercase()}"
        }

        return when {
            mimeType.contains("mpeg", ignoreCase = true) -> ".mp3"
            mimeType.contains("mp4", ignoreCase = true) || mimeType.contains("aac", ignoreCase = true) -> ".m4a"
            mimeType.contains("x-m4a", ignoreCase = true) -> ".m4a"
            mimeType.contains("flac", ignoreCase = true) -> ".flac"
            mimeType.contains("ogg", ignoreCase = true) -> ".ogg"
            mimeType.contains("wav", ignoreCase = true) -> ".wav"
            else -> ".mp3"
        }
    }

    private fun resolveDisplayName(context: Context, uri: Uri): String {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    if (index >= 0 && !cursor.isNull(index)) {
                        return cursor.getString(index) ?: ""
                    }
                }
                ""
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun readString(cursor: android.database.Cursor, index: Int): String {
        if (index < 0 || cursor.isNull(index)) return ""
        return cursor.getString(index) ?: ""
    }

    private fun readLong(cursor: android.database.Cursor, index: Int): Long {
        if (index < 0 || cursor.isNull(index)) return 0L
        return cursor.getLong(index)
    }

    private fun readInt(cursor: android.database.Cursor, index: Int): Int {
        if (index < 0 || cursor.isNull(index)) return 0
        return cursor.getInt(index)
    }
}
