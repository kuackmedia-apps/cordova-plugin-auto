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
    Log.i(TAG, "Image $imageId local: $exists")
    return exists
  }

  // Devuelve la URI claramente según disponibilidad local o remota
  fun getImageUri(context: Context, item: MediaBrowserCompat.MediaItem): Uri? {
    val imageId = item.description.mediaId + ".jpg"
    val imageFile = File(context.filesDir, "img/$imageId")

    if (imageFile.exists()) {
      Log.i(TAG, "Using local image: " + imageFile.absolutePath)
      return Uri.fromFile(imageFile)
    } else {
      val remoteUri = item.description.iconUri
      Log.i(TAG, "Using remote image: $remoteUri")
      return remoteUri
    }
  }

  fun getIconPath(context: Context, iconName: String): String {
    //String iconId = iconName;
    val iconFile = File(context.filesDir, iconName)
    val exists = iconFile.exists()
    Log.i(TAG, "Icon $iconName local: $exists")
    return iconFile.absolutePath
  }

  fun storeDataInPrefs(context: Context, key: String, data: String?) {
    Log.i(TAG, "Storing data in prefs: $key - $data")
    val prefs = context.getSharedPreferences("NativeStorage", MODE_PRIVATE)
    prefs.edit {
      putString(key, "\"$data\"")
    }
  }

  fun storeInFile(context: Context, key: String, data: String?) {
    Log.i(TAG, "Storing data in file: $key - $data")

    if(null !== data) {
      context.openFileOutput(key, MODE_PRIVATE).use { output ->
        output.write(data.toByteArray())
      }
    }
  }

  suspend fun getTrackUri(context: Context, trackId: String?, idAlbumTrack: String?): Uri? {
    Log.i(TAG, "[GET_TRACK_URI_START] Called with trackId=$trackId, idAlbumTrack=$idAlbumTrack")

    // Validate trackId
    if (trackId.isNullOrEmpty() || trackId == "null") {
      Log.e(TAG, "[GET_TRACK_URI_ERROR] Invalid trackId: $trackId")
      return null
    }

    val trackName = "$trackId.mp3"
    val trackFile = File(context.filesDir, "offline/$trackName")
    Log.d(TAG, "[GET_TRACK_URI_CHECK_LOCAL] Checking local file: ${trackFile.absolutePath}")

    if (trackFile.exists()) {
      Log.i(TAG, "[GET_TRACK_URI_LOCAL_FOUND] Using local track: ${trackFile.absolutePath}")
      return Uri.fromFile(trackFile)
    } else {
      Log.i(TAG, "[GET_TRACK_URI_REMOTE] Local file not found, attempting remote fetch")

      // Check if idAlbumTrack is valid
      if (idAlbumTrack.isNullOrEmpty() || idAlbumTrack == "null") {
        Log.e(TAG, "[GET_TRACK_URI_ERROR] Cannot fetch remote track: idAlbumTrack is invalid ($idAlbumTrack)")
        Log.e(TAG, "[GET_TRACK_URI_ERROR] This usually happens with offline tracks that don't have idAlbumTrack")
        return null
      }

      Log.d(TAG, "[GET_TRACK_URI_API_CALL] Creating API request with trackId=$trackId, idAlbumTrack=$idAlbumTrack")

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
        Log.i(TAG, "[GET_TRACK_URI_PAYLOAD] Track request payload: $payload")

        val url = api.getTrackUrl(payload).signedUrl
        Log.i(TAG, "[GET_TRACK_URI_SUCCESS] Track URL retrieved: $url")
        return url.toUri()
      } catch (e: Exception) {
        Log.e(TAG, "[GET_TRACK_URI_EXCEPTION] Failed to get track URL: ${e.message}", e)
        Log.e(TAG, "[GET_TRACK_URI_STACK_TRACE] ${e.stackTraceToString()}")
        return null
      }
    }
  }

}
