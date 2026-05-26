package com.hirumi.fastscanner

import android.content.ContentResolver
import android.content.ContentUris
import android.os.Build
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject

object FastAudioScanner {
    fun scan(resolver: ContentResolver): String {
        val out = JSONArray()
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.MIME_TYPE
        )

        val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "(${MediaStore.Audio.Media.IS_MUSIC} != 0 OR ${MediaStore.Audio.Media.MIME_TYPE} LIKE 'audio/%')"
        } else {
            "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        }

        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        resolver.query(uri, projection, selection, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val item = JSONObject()
                item.put("id", id)
                item.put("uri", ContentUris.withAppendedId(uri, id).toString())
                item.put("title", cursor.getString(titleCol) ?: "")
                item.put("artist", cursor.getString(artistCol) ?: "Desconhecido")
                item.put("album", cursor.getString(albumCol) ?: "Desconhecido")
                item.put("duration", cursor.getLong(durationCol))
                item.put("dateAdded", cursor.getLong(dateAddedCol))
                item.put("path", cursor.getString(dataCol) ?: "")
                item.put("mimeType", cursor.getString(mimeCol) ?: "")
                out.put(item)
            }
        }

        return out.toString()
    }
}
