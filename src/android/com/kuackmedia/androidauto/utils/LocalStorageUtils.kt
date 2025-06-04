package com.kuackmedia.androidauto.utils

import android.content.Context
import android.net.Uri
import android.support.v4.media.MediaBrowserCompat
import android.util.Log
import com.kuackmedia.androidauto.api.ServiceFactory
import com.kuackmedia.androidauto.models.TrackRequest
import java.io.File
import kotlin.String

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

  // Verifica claramente si un track está guardado localmente
  fun isTrackAvailableLocally(context: Context, item: MediaBrowserCompat.MediaItem): Boolean {
    val trackId = item.description.mediaId + ".mp3"
    val trackFile = File(context.filesDir, "tracks/$trackId")

    val exists = trackFile.exists()
    Log.i(TAG, "Track $trackId local: $exists")
    return exists
  }

  fun getIconPath(context: Context, iconName: String): String {
    //String iconId = iconName;
    val iconFile = File(context.filesDir, iconName)
    val exists = iconFile.exists()
    Log.i(TAG, "Icon $iconName local: $exists")
    return iconFile.absolutePath
  }

  suspend fun getTrackUri(context: Context, trackId: String?, idAlbumTrack: String?): Uri? {
    val trackName = "$trackId.mp3"
    val trackFile: File = File(context.filesDir, "playerTracks/$trackName")
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
      val url = api.getTrackUrl(payload).url
      Log.i(TAG, "[LocalStorageUtils] Track URL: $url")
      return Uri.parse(url)
    }
  }

}
