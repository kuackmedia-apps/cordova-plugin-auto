package com.kuackmedia.androidauto.media

import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log

object CurrentMedia {
  const val TAG = "CurrentMedia"

  fun getCurrentTrackFromQueue(
    currentTrack: String,
    currentQueue: List<MediaSessionCompat.QueueItem>?): MediaBrowserCompat.MediaItem? {

    val currentQueueItem = currentQueue
      ?.firstOrNull { it.description.extras?.getString("idAlbumTrack") == currentTrack }
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
}
