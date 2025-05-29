package com.kuackmedia.androidauto.utils

import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.IOException
import kotlin.text.toLong

object MediaUtils {
  private const val TAG = "MediaUtils"

  fun getMp3Duration(filePath: String): Long {
    val mmr = MediaMetadataRetriever()
    var duration: Long = 0
    try {
      if (filePath.startsWith("http://") || filePath.startsWith("https://")) {
        mmr.setDataSource(filePath, HashMap<String?, String?>()) // For URLs
      } else {
        mmr.setDataSource(filePath)
      }
      val durationStr = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
      if (durationStr != null) {
        duration = durationStr.toLong()
      }
    } catch (e: java.lang.Exception) {
      Log.e(TAG, "Error getting duration for: $filePath", e)
      return -1
    } finally {
      try {
        mmr.release() // Important to release the retriever
      } catch (e: IOException) {
        // Ignore, as it's already an error state
      }
    }
    return duration
  }
}
