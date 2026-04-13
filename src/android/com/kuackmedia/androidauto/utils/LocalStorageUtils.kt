package com.kuackmedia.androidauto.utils

import android.content.Context
import android.content.Context.MODE_PRIVATE
import android.net.Uri
import android.support.v4.media.MediaBrowserCompat
import android.util.Log
import com.kuackmedia.androidauto.api.ServiceFactory
import com.kuackmedia.androidauto.models.TrackRequest
import java.io.File
import kotlin.String
import androidx.core.net.toUri
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.CURRENT_TRACK_KEY
import androidx.core.content.edit

object LocalStorageUtils {
  private const val TAG = "LocalStorageUtils"

  // Verifica claramente si una imagen está guardada localmente
  fun isImageAvailableLocally(context: Context, item: MediaBrowserCompat.MediaItem): Boolean {
    val imageId = item.description.mediaId + ".jpg"
    val imageFile = File(context.filesDir, "images/$imageId")

    val exists = imageFile.exists()
    return exists
  }

  // Devuelve la URI claramente según disponibilidad local o remota
  fun getImageUri(context: Context, item: MediaBrowserCompat.MediaItem): Uri? {
    val imageId = item.description.mediaId + ".jpg"
    val imageFile = File(context.filesDir, "img/$imageId")

    if (imageFile.exists()) {
      return Uri.fromFile(imageFile)
    } else {
      val remoteUri = item.description.iconUri
      return remoteUri
    }
  }

  fun getIconPath(context: Context, iconName: String): String {
    //String iconId = iconName;
    val iconFile = File(context.filesDir, iconName)
    val exists = iconFile.exists()
    return iconFile.absolutePath
  }

  fun storeDataInPrefs(context: Context, key: String, data: String?) {
    val prefs = context.getSharedPreferences("NativeStorage", MODE_PRIVATE)
    prefs.edit {
      putString(key, "\"$data\"")
    }
  }

  /**
   * Stores data in a file using atomic write operation.
   * Uses temp file + rename pattern to prevent data corruption if the app
   * crashes or is killed during write operation.
   */
  fun storeInFile(context: Context, key: String, data: String?) {
    if (data == null) {
      return
    }

    val tempKey = "$key.tmp"
    val finalFile = File(context.filesDir, key)
    val tempFile = File(context.filesDir, tempKey)

    try {
      // Step 1: Write to temporary file
      tempFile.writeText(data, Charsets.UTF_8)

      // Step 2: Atomic rename from temp to final
      val renamed = tempFile.renameTo(finalFile)
      if (renamed) {
        // Rename successful
      } else {
        // Fallback: if rename fails (e.g., cross-filesystem), copy and delete
        tempFile.copyTo(finalFile, overwrite = true)
        tempFile.delete()
      }
    } catch (e: Exception) {
      Log.e(TAG, "storeInFile: failed to write file: $key - ${e.message}", e)
      // Clean up temp file on failure
      if (tempFile.exists()) {
        tempFile.delete()
      }
      throw e
    }
  }

  /**
   * Resolves a podcast episode audio URI.
   * 1. Check offline: Documents/offline/episodes/{episodeId}.mp3
   * 2. Fallback: enclosure URL (direct HTTP stream from RSS feed)
   */
  fun getEpisodeUri(context: Context, episodeId: String?, enclosureUrl: String?): Uri? {
    if (episodeId.isNullOrEmpty() || episodeId == "null") {
      Log.e(TAG, "[GET_EPISODE_URI] Invalid episodeId: $episodeId")
      return null
    }

    // Check offline episode file
    val episodeFile = File(context.filesDir, "offline/episodes/$episodeId.mp3")
    if (episodeFile.exists()) {
      return Uri.fromFile(episodeFile)
    }

    // Fallback to enclosure URL
    if (!enclosureUrl.isNullOrEmpty() && enclosureUrl != "null") {
      return Uri.parse(enclosureUrl)
    }

    Log.e(TAG, "[GET_EPISODE_URI_ERROR] No offline file and no enclosure URL for episodeId=$episodeId")
    return null
  }

  suspend fun getTrackUri(context: Context, trackId: String?, idAlbumTrack: String?): Uri? {
    // Validate trackId
    if (trackId.isNullOrEmpty() || trackId == "null") {
      Log.e(TAG, "[GET_TRACK_URI_ERROR] Invalid trackId: $trackId")
      return null
    }

    val trackName = "$trackId.mp3"

    // 1. Check user's offline downloads
    val trackFile = File(context.filesDir, "offline/$trackName")
    if (trackFile.exists()) {
      return Uri.fromFile(trackFile)
    }

    // 2. Check auto_cache (preloaded by TrackPreloader)
    val cacheFile = File(context.filesDir, "auto_cache/$trackName")
    if (cacheFile.exists()) {
      return Uri.fromFile(cacheFile)
    }

    run {
      // Check if idAlbumTrack is valid
      if (idAlbumTrack.isNullOrEmpty() || idAlbumTrack == "null") {
        Log.e(TAG, "[GET_TRACK_URI_ERROR] Cannot fetch remote track: idAlbumTrack is invalid ($idAlbumTrack)")
        Log.e(TAG, "[GET_TRACK_URI_ERROR] This usually happens with offline tracks that don't have idAlbumTrack")
        return null
      }

      try {
        val api = ServiceFactory.create(context)
        val payload = TrackRequest(
          idAlbumTrack = idAlbumTrack,
          idTrack = trackId,
          forceDevice = false,
          useCloudFront = true,
          forcePreview = false,
          extraLife = false,
        )

        val url = api.getTrackUrl(payload).signedUrl
        return url.toUri()
      } catch (e: Exception) {
        Log.e(TAG, "[GET_TRACK_URI_EXCEPTION] Failed to get track URL: ${e.message}", e)
        Log.e(TAG, "[GET_TRACK_URI_STACK_TRACE] ${e.stackTraceToString()}")
        return null
      }
    }
  }

}
