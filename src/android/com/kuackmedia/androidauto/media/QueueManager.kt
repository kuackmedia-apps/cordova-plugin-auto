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

    // Reset currentQueueIndex when building new queue
    currentQueueIndex = 0
    Log.i(TAG, "[BUILD_QUEUE] Built queue with ${this.queue?.size ?: 0} items, reset currentQueueIndex to 0")
  }

  fun setQueue(mediaSession: MediaSessionCompat,) {
    CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE, JSONObject())
    mediaSession.setQueue(queue)

    // Validate currentQueueIndex after setting queue
    val queueSize = queue?.size ?: 0
    if (currentQueueIndex >= queueSize && queueSize > 0) {
      Log.w(TAG, "[SET_QUEUE] currentQueueIndex ($currentQueueIndex) >= queue.size ($queueSize), resetting to 0")
      currentQueueIndex = 0
    }
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
      try {
        val jsonArray = jsonFile.readText(Charsets.UTF_8)

        // Validate that file is not empty
        if (jsonArray.isBlank()) {
          Log.w(TAG, "QUEUE file is empty")
          return null
        }

        // Validate that content looks like JSON
        val trimmed = jsonArray.trim()
        if (!trimmed.startsWith("[") && !trimmed.startsWith("{")) {
          Log.e(TAG, "QUEUE file does not contain valid JSON format")
          jsonFile.delete()
          return null
        }

        Log.i(TAG, "QUEUE FILE: $jsonArray")
        val listType = Types.newParameterizedType(List::class.java, QueueItem::class.java)
        val adapter: JsonAdapter<List<QueueItem>> = moshi.adapter(listType)
        val items: List<QueueItem>? = adapter.fromJson(jsonArray)
        Log.i(TAG, "QUEUE_ITEMS_KEY_RAW: $items")

        this.queue = items
          ?.mapNotNull { it.data } // Use mapNotNull to filter out null data
          ?.filter { it !is EmptyModel }
          ?.mapNotNull { // Use mapNotNull to handle parsing errors gracefully
            try {
              MediaItemFactory.parseMediaItems(it, "", context)
            } catch (e: Exception) {
              Log.w(TAG, "Failed to parse queue item: ${e.message}")
              null
            }
          }
          ?.mapIndexed { index, track ->
            MediaSessionCompat.QueueItem(track.description, index.toLong())
          }

        Log.i(TAG, "QUEUE_ITEMS_KEY: ${this.queue}")
        return this.queue

      } catch (e: com.squareup.moshi.JsonDataException) {
        Log.e(TAG, "JSON data exception in QUEUE file: ${e.message}", e)
        jsonFile.delete() // Delete corrupted file
        return null
      } catch (e: com.squareup.moshi.JsonEncodingException) {
        Log.e(TAG, "JSON encoding exception in QUEUE file: ${e.message}", e)
        jsonFile.delete() // Delete corrupted file
        return null
      } catch (e: java.io.EOFException) {
        Log.e(TAG, "Incomplete JSON file in QUEUE (EOF): ${e.message}", e)
        jsonFile.delete() // Delete corrupted file
        return null
      } catch (e: Exception) {
        Log.e(TAG, "Unexpected error reading QUEUE file: ${e.message}", e)
        // Don't delete file on unexpected errors, might be recoverable
        return null
      }
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

    // Validate that currentQueueIndex is within bounds
    if (currentQueueIndex >= queue.size) {
      Log.w(TAG, "[GET_NEXT] currentQueueIndex ($currentQueueIndex) >= queue.size (${queue.size}), resetting to 0")
      currentQueueIndex = 0
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

    // Validate that currentQueueIndex is within bounds
    if (currentQueueIndex >= queue.size) {
      Log.w(TAG, "[GET_PREVIOUS] currentQueueIndex ($currentQueueIndex) >= queue.size (${queue.size}), resetting to last item")
      currentQueueIndex = queue.size - 1
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
    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
      Log.w(TAG, "[GET_ITEM] Queue is null or empty")
      return null
    }

    val requestedIndex = id.toInt()

    // Validate that the requested index is within bounds
    if (requestedIndex < 0 || requestedIndex >= queue.size) {
      Log.e(TAG, "[GET_ITEM] Requested index $requestedIndex is out of bounds (queue size: ${queue.size})")
      return null
    }

    currentQueueIndex = requestedIndex
    return queue[currentQueueIndex]
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
