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
  const val TAG = "CURRENT_MEDIA"

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

  fun getCurrentQueue(context: Context): List<MediaSessionCompat.QueueItem>? {
    val mediaItemAdapter = MediaItemJsonAdapter(
        Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()
    )
    val moshi = Moshi.Builder()
      .add(MediaItem::class.java, mediaItemAdapter)
      .add(KotlinJsonAdapterFactory())
      .build()

    val jsonFile = File(context.filesDir, "QUEUE_ITEMS_KEY")
    val jsonArray = jsonFile.readText(Charsets.UTF_8)
    val listType = Types.newParameterizedType(List::class.java, QueueItem::class.java)
    val adapter: JsonAdapter<List<QueueItem>> = moshi.adapter(listType)
    val items: List<QueueItem>? = adapter.fromJson(jsonArray)
    Log.i(TAG, "QUEUE_ITEMS_KEY_RAW: $items")
    val queueJsonObjects = items
      ?.map { it.data }
      ?.filter { it !is EmptyModel }
      ?.map { MediaItemFactory.parseMediaItems(it)!! }
      ?.mapIndexed { index, track ->
        MediaSessionCompat.QueueItem(track.description, index.toLong())
      }

    Log.i(TAG, "QUEUE_ITEMS_KEY: $queueJsonObjects")
    return queueJsonObjects
  }
}
