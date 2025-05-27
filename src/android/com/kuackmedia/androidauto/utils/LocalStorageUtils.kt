package com.kuackmedia.androidauto.utils

import android.content.Context
import android.net.Uri
import android.support.v4.media.MediaBrowserCompat
import android.util.Log
import java.io.File

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

  // Devuelve la URI claramente según disponibilidad local o remota
//  fun getTrackUri(trackId: String?): Uri? {
//    val trackName = trackId + ".mp3"
//    val trackFile = File(context!!.getFilesDir(), "playerTracks/" + trackName)
//    //file:///data/user/0/com.algar.nomomusica/files/playerTracks/12180191.mp3
//    Log.i(TAG, "getTrackUri " + trackName)
//    if (trackFile.exists()) {
//      Log.i(TAG, "Using local track: " + trackFile.getAbsolutePath())
//      return Uri.fromFile(trackFile)
//    } else {
//      val remoteTrackFile = File(context!!.getFilesDir(), "playerTracks/49234.mp3")
//      Log.i(TAG, "Using remote track: " + remoteTrackFile.getAbsolutePath())
//      return Uri.fromFile(remoteTrackFile)
//    }
//  }

}
