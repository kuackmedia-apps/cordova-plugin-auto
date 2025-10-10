package com.kuackmedia.androidauto.utils

import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.File
import java.io.FileInputStream
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
        val file = File(filePath)
        if (!file.exists()) return -1
        val fis = FileInputStream(file)
        mmr.setDataSource(fis.fd)
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
  fun parseDuration(duration: String?): Long {
    if (duration.isNullOrEmpty()) {
      return 0
    }

    return try {
      val parts = duration.split(":")
      when (parts.size) {
        3 -> { // HH:MM:SS
          val hours = parts[0].toLong()
          val minutes = parts[1].toLong()
          val seconds = parts[2].toLong()
          ((hours * 3600) + (minutes * 60) + seconds) * 1000
        }
        2 -> { // MM:SS
          val minutes = parts[0].toLong()
          val seconds = parts[1].toLong()
          ((minutes * 60) + seconds) * 1000
        }
        else -> 0
      }
    } catch (e: NumberFormatException) {
      Log.e(TAG, "Failed to parse duration: $duration", e)
      0
    }
  }
}
