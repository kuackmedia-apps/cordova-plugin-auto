package com.kuackmedia.androidauto.media

import android.content.Context
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import com.kuackmedia.androidauto.models.EmptyModel
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.QueueItem
import com.kuackmedia.androidauto.tree.MediaItemFactory
import com.kuackmedia.androidauto.tree.MediaItemJsonAdapter
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File

object CurrentMedia {
  const val TAG = "CurrentMedia"

  fun getCurrentTrackFromQueue(
    currentTrack: String,
    currentQueue: List<MediaSessionCompat.QueueItem>?): MediaBrowserCompat.MediaItem? {
    val currentQueueItem = currentQueue
      ?.firstOrNull { it.description.title.toString() == currentTrack }
      ?.also { Log.i(TAG, "found current track: ${it.description.title}") }

    return if(currentQueueItem !== null) {
      MediaBrowserCompat.MediaItem(
        currentQueueItem.description,
        MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
      )
    } else null
  }
}
