package com.kuackmedia.androidauto.media

import android.content.Context
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import com.kuackmedia.androidauto.CordovaEventBridge
import com.kuackmedia.androidauto.CordovaEvents
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
import org.json.JSONObject
import java.io.File

object QueueManager {
  const val TAG = "QueueBuilder"
  private var currentQueueIndex = 0
  private var queue:  List<MediaSessionCompat.QueueItem>? = null

  fun buildQueue(items: List<MediaBrowserCompat.MediaItem>) {

    this.queue = items
      .mapIndexed { index, track ->
        MediaSessionCompat.QueueItem(track.description, index.toLong())
      }
  }

  fun setQueue(mediaSession: MediaSessionCompat,) {
    CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE, JSONObject())
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
      this.queue = items
        ?.map { it.data }
        ?.filter { it !is EmptyModel }
        ?.map { MediaItemFactory.parseMediaItems(it, "", context)!! }
        ?.mapIndexed { index, track ->
          MediaSessionCompat.QueueItem(track.description, index.toLong())
        }

      Log.i(TAG, "QUEUE_ITEMS_KEY: ${this.queue}")
      return  this.queue
    } else {
      return null
    }
  }

  fun getNextQueueItem(mediaSession: MediaSessionCompat): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
      Log.w(TAG, "[GET_NEXT] Queue is null or empty")
      return null
    }

    // If we're at the end of the queue, loop back to the beginning
    if (currentQueueIndex + 1 >= queue.size) {
      Log.i(TAG, "[GET_NEXT] Reached end of queue (index $currentQueueIndex of ${queue.size}), looping to start")
      currentQueueIndex = 0
    } else {
      currentQueueIndex += 1
      Log.i(TAG, "[GET_NEXT] Moving to next track, index: $currentQueueIndex")
    }

    return queue[currentQueueIndex]
  }

  fun getPreviousQueueItem(mediaSession: MediaSessionCompat): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
      Log.w(TAG, "[GET_PREVIOUS] Queue is null or empty")
      return null
    }

    // If we're at the beginning of the queue, loop back to the end
    if (currentQueueIndex - 1 < 0) {
      Log.i(TAG, "[GET_PREVIOUS] At start of queue (index $currentQueueIndex), looping to end")
      currentQueueIndex = queue.size - 1
    } else {
      currentQueueIndex -= 1
      Log.i(TAG, "[GET_PREVIOUS] Moving to previous track, index: $currentQueueIndex")
    }

    return queue[currentQueueIndex]
  }

  fun getItem(mediaSession: MediaSessionCompat, id: Long): MediaSessionCompat.QueueItem? {
    currentQueueIndex = id.toInt()
    return mediaSession.controller.queue[id.toInt()]
  }

  /**
   * Synchronize currentQueueIndex with the currently playing track.
   * This should be called when a track starts playing to ensure next/previous work correctly.
   */
  fun syncCurrentIndex(mediaSession: MediaSessionCompat, currentMediaId: String?) {
    if (currentMediaId == null) {
      Log.w(TAG, "[SYNC_INDEX] currentMediaId is null, cannot sync")
      return
    }

    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
      Log.w(TAG, "[SYNC_INDEX] Queue is null or empty, cannot sync")
      return
    }

    // Find the index of the current track in the queue
    val index = queue.indexOfFirst { it.description.mediaId == currentMediaId }

    if (index >= 0) {
      currentQueueIndex = index
      Log.i(TAG, "[SYNC_INDEX] Synchronized index to $currentQueueIndex for mediaId: $currentMediaId")
    } else {
      Log.w(TAG, "[SYNC_INDEX] Could not find mediaId '$currentMediaId' in queue, keeping current index: $currentQueueIndex")
    }
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
