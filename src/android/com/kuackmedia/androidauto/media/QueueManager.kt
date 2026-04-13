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
import com.kuackmedia.androidauto.utils.TextsManager
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
  }

  fun setQueue(mediaSession: MediaSessionCompat, queueTitle: String? = null) {
    CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE, JSONObject())
    mediaSession.setQueue(queue)
    if (!queueTitle.isNullOrEmpty()) {
      mediaSession.setQueueTitle(queueTitle)
    }

    // Validate currentQueueIndex after setting queue
    val queueSize = queue?.size ?: 0
    if (currentQueueIndex >= queueSize && queueSize > 0) {
      currentQueueIndex = 0
    }
  }

  fun buildQueueTitle(type: String, name: String): String {
    val prefix = TextsManager.getText("queue_title").ifEmpty { "Playing from " }
    val typeLabel = when (type.uppercase()) {
      "PLAYLIST" -> TextsManager.getText("queue_playlist")
      "ALBUM" -> TextsManager.getText("queue_album")
      "ARTIST" -> TextsManager.getText("queue_artist")
      "TRACK_RADIO" -> TextsManager.getText("queue_radioTrack")
      "ARTIST_STATION" -> TextsManager.getText("queue_radioArtist")
      "RADIO" -> TextsManager.getText("queue_station")
      "MIX" -> TextsManager.getText("queue_mix")
      "PODCAST" -> TextsManager.getText("queue_podcast")
      else -> type
    }.ifEmpty { type }
    return "$prefix$typeLabel: $name"
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
          return null
        }

        // Validate that content looks like JSON
        val trimmed = jsonArray.trim()
        if (!trimmed.startsWith("[") && !trimmed.startsWith("{")) {
          Log.e(TAG, "QUEUE file does not contain valid JSON format")
          jsonFile.delete()
          return null
        }

        val listType = Types.newParameterizedType(List::class.java, QueueItem::class.java)
        val adapter: JsonAdapter<List<QueueItem>> = moshi.adapter(listType)
        val items: List<QueueItem>? = adapter.fromJson(jsonArray)

        this.queue = items
          ?.mapNotNull { it.data } // Use mapNotNull to filter out null data
          ?.filter { it !is EmptyModel }
          ?.mapNotNull { // Use mapNotNull to handle parsing errors gracefully
            try {
              MediaItemFactory.parseMediaItems(it, "", context)
            } catch (e: Exception) {
              null
            }
          }
          ?.mapIndexed { index, track ->
            MediaSessionCompat.QueueItem(track.description, index.toLong())
          }

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
      return null
    }

    // Validate that currentQueueIndex is within bounds
    if (currentQueueIndex >= queue.size) {
      currentQueueIndex = 0
    }

    // If we're at the end of the queue, loop back to the beginning
    if (currentQueueIndex + 1 >= queue.size) {
      currentQueueIndex = 0
    } else {
      currentQueueIndex += 1
    }

    return queue[currentQueueIndex]
  }

  fun getPreviousQueueItem(mediaSession: MediaSessionCompat): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
      return null
    }

    // Validate that currentQueueIndex is within bounds
    if (currentQueueIndex >= queue.size) {
      currentQueueIndex = queue.size - 1
    }

    // If we're at the beginning of the queue, loop back to the end
    if (currentQueueIndex - 1 < 0) {
      currentQueueIndex = queue.size - 1
    } else {
      currentQueueIndex -= 1
    }

    return queue[currentQueueIndex]
  }

  fun getItem(mediaSession: MediaSessionCompat, id: Long): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
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
      return
    }

    val queue = mediaSession.controller.queue
    if (queue == null || queue.isEmpty()) {
      return
    }

    // Find the index of the current track in the queue
    val index = queue.indexOfFirst { it.description.mediaId == currentMediaId }

    if (index >= 0) {
      currentQueueIndex = index
    }
  }

  /**
   * Appends tracks to the end of the existing queue without resetting currentQueueIndex.
   * Returns the number of items appended.
   */
  fun appendQueue(
    newItems: List<MediaBrowserCompat.MediaItem>,
    mediaSession: MediaSessionCompat
  ): Int {
    val currentQueue = this.queue?.toMutableList() ?: mutableListOf()
    val startIndex = currentQueue.size

    val newQueueItems = newItems.mapIndexed { index, track ->
      MediaSessionCompat.QueueItem(track.description, (startIndex + index).toLong())
    }

    currentQueue.addAll(newQueueItems)
    this.queue = currentQueue
    mediaSession.setQueue(this.queue)

    return newItems.size
  }

  fun shouldLoadMore(threshold: Int = 3): Boolean {
    val queueSize = queue?.size ?: return false
    val remaining = queueSize - currentQueueIndex - 1
    return remaining <= threshold
  }

  fun getCurrentQueueIndex(): Int = currentQueueIndex

  fun getQueueSize(): Int = queue?.size ?: 0

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
