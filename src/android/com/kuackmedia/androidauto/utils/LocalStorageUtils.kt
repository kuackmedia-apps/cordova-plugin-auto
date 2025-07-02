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

    if(data !== null) {
      context.openFileOutput(key, MODE_PRIVATE).use { output ->
        output.write(data.toByteArray())
      }
    }
  }

  suspend fun getTrackUri(context: Context, trackId: String?, idAlbumTrack: String?): Uri? {
    val trackName = "$trackId.mp3"
    val trackFile = File(context.filesDir, "playerTracks/$trackName")
    //file:///data/user/0/com.algar.nomomusica/files/playerTracks/12180191.mp3
    Log.i(TAG, "getTrackUri $trackName")
    if (trackFile.exists()) {
      Log.i(TAG, "Using local track: " + trackFile.absolutePath)
      return Uri.fromFile(trackFile)
    } else {
      Log.i(TAG, "Using remote track: $trackId")
      val api = ServiceFactory.create(context)
      val payload = TrackRequest(
        idAlbumTrack = idAlbumTrack!!,
        idTrack = trackId!!,
        forceDevice = false,
        useCloudFront =  true,
        forcePreview = false,
        extraLife = false,
      )
      Log.i(TAG, "[LocalStorageUtils] Track payload: $payload")
      val url = api.getTrackUrl(payload).signedUrl
      Log.i(TAG, "[LocalStorageUtils] Track URL: $url")
      return url.toUri()
    }
  }

}
