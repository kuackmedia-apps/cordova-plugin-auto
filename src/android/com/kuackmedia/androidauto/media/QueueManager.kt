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
import com.kuackmedia.androidauto.utils.LocalStorageUtils
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File

object QueueManager {
  const val TAG = "QueueBuilder"
  private var currentQueueIndex = 0

  fun buildQueue(
    mediaSession: MediaSessionCompat,
    items: List<MediaBrowserCompat.MediaItem>) {

    val queue = items
      .mapIndexed { index, track ->
        MediaSessionCompat.QueueItem(track.description, index.toLong())
      }

    mediaSession.setQueue(queue)
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

    if (jsonFile.exists()) {
      val jsonArray = jsonFile.readText(Charsets.UTF_8)
      Log.i(TAG, "QUEUE FILE: $jsonArray")
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
    } else {
      return null
    }
  }

  fun getNextQueueItem(mediaSession: MediaSessionCompat): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    return if (queue != null && currentQueueIndex + 1 < queue.size) {
      currentQueueIndex += 1
      queue[currentQueueIndex]
    } else {
      null
    }
  }

  fun getPreviousQueueItem(mediaSession: MediaSessionCompat): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    return if (queue != null && currentQueueIndex - 1 > 0) {
      currentQueueIndex -= 1
      queue[currentQueueIndex]
    } else {
      null
    }
  }

  fun getItem(mediaSession: MediaSessionCompat, id: Long): MediaSessionCompat.QueueItem? {
    currentQueueIndex = id.toInt()
    return mediaSession.controller.queue[id.toInt()]
  }

  private fun isAlreadyInQueue(
    mediaSession: MediaSessionCompat,
    track: MediaBrowserCompat.MediaItem): Boolean {

    val queue = mediaSession.controller.queue
    for (item in queue) {
      if (item.description.mediaId == track.mediaId) {
        return true
      }
    }
    return false
  }
}
