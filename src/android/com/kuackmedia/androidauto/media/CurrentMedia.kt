package com.kuackmedia.androidauto.media

import android.content.Context
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import java.io.File

object CurrentMedia {
  const val TAG = "CurrentMedia"

  fun getCurrentTrackFromQueue(
    currentTrack: String,
    currentQueue: List<MediaSessionCompat.QueueItem>?): MediaBrowserCompat.MediaItem? {

    Log.i(TAG, "[getCurrentTrackFromQueue] Current queue: $currentQueue")
    val currentQueueItem = currentQueue
      ?.firstOrNull {
        Log.i(TAG, "[getCurrentTrackFromQueue] Queue compare it ${it.description.extras}")
        it.description.extras?.getString("idAlbumTrack") == currentTrack
      }
      ?.also { Log.i(TAG, "found current track: ${it.description.title}") }

    Log.i(TAG, "Finding current track: $currentTrack")
    Log.i(TAG, "Finding current Queue item: $currentQueueItem")

    return if(currentQueueItem !== null) {
      MediaBrowserCompat.MediaItem(
        currentQueueItem.description,
        MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
      )
    } else null
  }

  /**
   * Reads raw file content from context.filesDir.
   * Used by onPrepare() to read PLAYLIST_DATA and current_episode files.
   */
  fun readFileContent(context: Context, fileName: String): String? {
    val file = File(context.filesDir, fileName)
    return if (file.exists()) {
      try {
        val content = file.readText(Charsets.UTF_8)
        Log.d(TAG, "[readFileContent] Read ${content.length} bytes from $fileName")
        content
      } catch (e: Exception) {
        Log.e(TAG, "[readFileContent] Error reading $fileName: ${e.message}", e)
        null
      }
    } else {
      Log.d(TAG, "[readFileContent] File not found: $fileName")
      null
    }
  }
}
