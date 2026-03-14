package com.kuackmedia.androidauto.media

import android.content.Context
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import com.kuackmedia.androidauto.api.ServiceFactory
import com.kuackmedia.androidauto.models.TrackRequest
import kotlinx.coroutines.*
import java.io.File
import java.net.URL

/**
 * Preloads the next N tracks from the queue as MP3 files in auto_cache/ directory.
 * Downloads sequentially, one at a time, and pauses when MediaPlayer is buffering
 * to avoid competing for bandwidth.
 */
object TrackPreloader {
  private const val TAG = "TrackPreloader"
  private const val CACHE_DIR = "auto_cache"
  private const val PRELOAD_WINDOW = 10
  private const val BUFFERING_CHECK_INTERVAL_MS = 500L

  private var preloadJob: Job? = null
  private var isBuffering = false

  /**
   * Called by MediaSessionCallback when playback state changes to BUFFERING or PLAYING.
   */
  fun onPlaybackStateChanged(isBufferingNow: Boolean) {
    isBuffering = isBufferingNow
  }

  /**
   * Main entry point. Cancels any previous preload job, cleans up files outside the
   * current window, and starts downloading the next PRELOAD_WINDOW tracks.
   */
  fun preloadNextTracks(context: Context, mediaSession: MediaSessionCompat) {
    preloadJob?.cancel()
    preloadJob = CoroutineScope(Dispatchers.IO).launch {
      try {
        val queue = mediaSession.controller.queue
        if (queue.isNullOrEmpty()) {
          Log.w(TAG, "[PRELOAD] Queue is empty, nothing to preload")
          return@launch
        }

        val currentIndex = QueueManager.getCurrentQueueIndex()
        val queueSize = queue.size

        // Collect trackIds in the preload window (current+1 to current+PRELOAD_WINDOW)
        val windowTrackIds = mutableSetOf<String>()
        val tracksToPreload = mutableListOf<PreloadTrackInfo>()

        for (i in 1..PRELOAD_WINDOW) {
          val idx = currentIndex + i
          if (idx >= queueSize) break

          val item = queue[idx]
          val extras = item.description.extras ?: continue
          val trackId = extras.getString("id") ?: continue
          val idAlbumTrack = extras.getString("idAlbumTrack") ?: continue

          windowTrackIds.add(trackId)

          // Skip if already in user's offline directory
          val offlineFile = File(context.filesDir, "offline/$trackId.mp3")
          if (offlineFile.exists()) {
            Log.d(TAG, "[PRELOAD] Track $trackId already offline, skip")
            continue
          }

          // Skip if already cached
          val cacheFile = File(context.filesDir, "$CACHE_DIR/$trackId.mp3")
          if (cacheFile.exists()) {
            Log.d(TAG, "[PRELOAD] Track $trackId already cached, skip")
            continue
          }

          tracksToPreload.add(PreloadTrackInfo(trackId, idAlbumTrack))
        }

        // Clean up cached files NOT in the current window
        cleanupOutsideWindow(context, windowTrackIds)

        if (tracksToPreload.isEmpty()) {
          Log.i(TAG, "[PRELOAD] All tracks in window are available, nothing to download")
          return@launch
        }

        Log.i(TAG, "[PRELOAD] Starting preload of ${tracksToPreload.size} tracks (window: ${currentIndex + 1} to ${minOf(currentIndex + PRELOAD_WINDOW, queueSize - 1)})")

        // Ensure cache directory exists
        val cacheDir = File(context.filesDir, CACHE_DIR)
        if (!cacheDir.exists()) {
          cacheDir.mkdirs()
        }

        // Clean up orphan .tmp files
        cacheDir.listFiles()?.filter { it.name.endsWith(".tmp") }?.forEach { tmpFile ->
          Log.d(TAG, "[PRELOAD] Deleting orphan tmp file: ${tmpFile.name}")
          tmpFile.delete()
        }

        // Download sequentially
        for (track in tracksToPreload) {
          if (!isActive) {
            Log.i(TAG, "[PRELOAD] Job cancelled, stopping")
            return@launch
          }

          // Wait while player is buffering
          while (isBuffering && isActive) {
            Log.d(TAG, "[PRELOAD] Player is buffering, pausing preload...")
            delay(BUFFERING_CHECK_INTERVAL_MS)
          }

          if (!isActive) return@launch

          downloadTrack(context, track)
        }

        Log.i(TAG, "[PRELOAD] Preload complete")
      } catch (e: CancellationException) {
        Log.i(TAG, "[PRELOAD] Job cancelled")
      } catch (e: Exception) {
        Log.e(TAG, "[PRELOAD] Error: ${e.message}", e)
      }
    }
  }

  /**
   * Downloads a single track MP3 to auto_cache/ using temp+rename for atomicity.
   */
  private suspend fun downloadTrack(context: Context, track: PreloadTrackInfo) {
    try {
      Log.i(TAG, "[DOWNLOAD] Fetching URL for track ${track.trackId}")

      // 1. Get signed URL from API
      val api = ServiceFactory.create(context)
      val payload = TrackRequest(
        idAlbumTrack = track.idAlbumTrack,
        idTrack = track.trackId,
        forceDevice = false,
        useCloudFront = true,
        forcePreview = false,
        extraLife = false,
      )
      val signedUrl = api.getTrackUrl(payload).signedUrl
      Log.i(TAG, "[DOWNLOAD] Got URL for track ${track.trackId}, downloading...")

      // 2. Download to temp file
      val cacheDir = File(context.filesDir, CACHE_DIR)
      val tmpFile = File(cacheDir, "${track.trackId}.tmp")
      val finalFile = File(cacheDir, "${track.trackId}.mp3")

      withContext(Dispatchers.IO) {
        val url = URL(signedUrl)
        url.openStream().use { input ->
          tmpFile.outputStream().use { output ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            var totalBytes = 0L
            while (input.read(buffer).also { bytesRead = it } != -1) {
              // Check cancellation periodically
              if (!coroutineContext.isActive) {
                tmpFile.delete()
                return@withContext
              }
              output.write(buffer, 0, bytesRead)
              totalBytes += bytesRead
            }
            Log.i(TAG, "[DOWNLOAD] Downloaded ${totalBytes / 1024}KB for track ${track.trackId}")
          }
        }

        // 3. Atomic rename
        if (tmpFile.exists() && tmpFile.length() > 0) {
          val renamed = tmpFile.renameTo(finalFile)
          if (renamed) {
            Log.i(TAG, "[DOWNLOAD] Cached track ${track.trackId} (${finalFile.length() / 1024}KB)")
          } else {
            tmpFile.copyTo(finalFile, overwrite = true)
            tmpFile.delete()
            Log.i(TAG, "[DOWNLOAD] Cached track ${track.trackId} via copy fallback")
          }
        } else {
          Log.w(TAG, "[DOWNLOAD] Temp file empty or missing for track ${track.trackId}")
          tmpFile.delete()
        }
      }
    } catch (e: CancellationException) {
      // Clean up temp file on cancellation
      val tmpFile = File(context.filesDir, "$CACHE_DIR/${track.trackId}.tmp")
      tmpFile.delete()
      throw e
    } catch (e: Exception) {
      Log.e(TAG, "[DOWNLOAD] Failed to download track ${track.trackId}: ${e.message}")
      // Clean up temp file on error
      val tmpFile = File(context.filesDir, "$CACHE_DIR/${track.trackId}.tmp")
      tmpFile.delete()
      // Continue with next track (don't rethrow)
    }
  }

  /**
   * Deletes cached files that are NOT in the current preload window.
   */
  private fun cleanupOutsideWindow(context: Context, windowTrackIds: Set<String>) {
    val cacheDir = File(context.filesDir, CACHE_DIR)
    if (!cacheDir.exists()) return

    cacheDir.listFiles()?.forEach { file ->
      val trackId = file.nameWithoutExtension
      if (trackId !in windowTrackIds) {
        file.delete()
        Log.d(TAG, "[CLEANUP] Removed ${file.name} (outside window)")
      }
    }
  }

  /**
   * Clears all files in auto_cache/. Called when AA session starts.
   */
  fun clearCache(context: Context) {
    preloadJob?.cancel()
    val cacheDir = File(context.filesDir, CACHE_DIR)
    if (cacheDir.exists()) {
      val count = cacheDir.listFiles()?.size ?: 0
      cacheDir.deleteRecursively()
      Log.i(TAG, "[CLEAR_CACHE] Deleted $count cached files")
    }
  }

  private data class PreloadTrackInfo(
    val trackId: String,
    val idAlbumTrack: String
  )
}
