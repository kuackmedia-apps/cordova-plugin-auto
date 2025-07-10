package com.kuackmedia.androidauto.media

import android.content.Context
import android.content.Context.MODE_PRIVATE
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import com.kuackmedia.androidauto.CordovaEventBridge
import com.kuackmedia.androidauto.CordovaEvents
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.CURRENT_TRACK_KEY
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.QUEUE_ITEMS_KEY
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.PLAYLIST_DATA
import com.kuackmedia.androidauto.utils.LocalStorageUtils
import com.kuackmedia.androidauto.utils.MediaUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject


/**
 * Routes transport controls to your PlayerAdapter and
 * keeps the session’s PlaybackState in sync.
 */
class MediaSessionCallback(
  private val mediaPlayer: IPlayerAdapter,
  private val mediaSession: MediaSessionCompat,
  private val context: Context
) : MediaSessionCompat.Callback() {

  companion object {
    private const val PLAYBACK_POSITION_UPDATE_INTERVAL: Long = 1000
    private const val TAG = "MediaSessionCallback"
  }

  private val handler: Handler = Handler(Looper.getMainLooper())
  private var currentQueue: List<MediaSessionCompat.QueueItem>? = null
  private var currentTrack: MediaBrowserCompat.MediaItem? = null

  init {
    // This executes when a track ends playing
    mediaPlayer.setOnCompletionListener {
      handlePlaybackCompletion()
    }

    // This executes when the track is loaded into the player
    mediaPlayer.setOnPreparedListener {
      handlePrepare()
    }

    // This executes on error
    mediaPlayer.setOnErrorListener { what, extra ->
      handleError(what, extra)
    }
  }

  override fun onPrepare() {
    Log.d(TAG, "onPrepare triggered")

    val prefs = this.context.getSharedPreferences("NativeStorage", MODE_PRIVATE)
    this.currentQueue = QueueManager.getCurrentQueue(this.context)
    if(currentQueue !== null) {
      Log.d(TAG, "Current queue: $currentQueue")
      this.currentTrack =
        CurrentMedia.getCurrentTrackFromQueue(
          prefs.getString(CURRENT_TRACK_KEY, null).toString().replace("\"", ""),
          this.currentQueue
        )
      Log.i(TAG, "Current track: ${this.currentTrack}")

      mediaPlayer.currentTrackFromApp = true
      this.onPlayFromMediaId(this.currentTrack?.mediaId, this.currentTrack?.description?.extras)
    }
  }

  override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
    val mediaSessionContext = extras?.getString("MEDIA_SESSION_SERVICE_CONTEXT")

    if (mediaSessionContext == "MEDIA_AUTOPLAY") {
      Log.d(TAG, "Blocking autoplay triggered by Android Auto")
      // Optionally reset state or ignore
      return
    }

    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[onPlayFromMediaId] Start $mediaId")
      val trackId = extras?.getString("idAlbumTrack")
      Log.i(TAG, "[onPlayFromMediaId] trackId $trackId")

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val trackUrl: Uri? = LocalStorageUtils.getTrackUri(context, extras?.getString("id"),
            trackId)
          withContext(Dispatchers.Main) {
            Log.i(TAG, "[onPlayFromMediaId] Current track $trackUrl")
            QueueManager.setQueue(mediaSession)
            mediaPlayer.setCurrentTrack(trackUrl)
            mediaPlayer.playCurrentTrack(context)

            updateState(PlaybackStateCompat.STATE_BUFFERING, 0)

            val duration = extras?.getLong("Length")?.let {
              if (it <= 0) MediaUtils.getMp3Duration(trackUrl.toString())
              else it
            }
            Log.i(TAG, "[onPlayFromMediaId] Duration $duration")

            val metadata = MediaMetadataCompat.Builder()
              .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras?.getString("title"))
              .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras?.getString("artist"))
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras?.getString("album"))
              .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, extras?.getString("image"))
              .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration!!)
              .build()

            mediaSession.setMetadata(metadata)

            storeLocalData(extras, trackId)
          }
        } catch (e: Exception) {
          Log.e("MediaSession", "Failed to load track URI", e)
        }
      }
    }
  }

  override fun onPlay() {
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.play()
      updateState(PlaybackStateCompat.STATE_PLAYING)
      handler.post(updatePlaybackPositionRunnable)
      mediaSession.isActive = true
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "play"))
    }
  }

  override fun onStop() {
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.stop()
      updateState(PlaybackStateCompat.STATE_STOPPED, 0)
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "stop"))
    }
  }

  override fun onPause() {
    Log.d(TAG, "Pausing at position: ${mediaPlayer.currentPosition}")
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.pause()
      updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "pause"))
    }
  }

  override fun onSkipToNext() {
    if(!mediaPlayer.isPreparing()) {
      val nextItem = QueueManager.getNextQueueItem(mediaSession)?.description
      onPlayFromMediaId(
        mediaId = nextItem?.mediaId,
        extras = nextItem?.extras
      )
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToNext"))
    }
  }

  override fun onSkipToPrevious() {
    if(!mediaPlayer.isPreparing()) {
      val previousItem = QueueManager.getPreviousQueueItem(mediaSession)?.description
      onPlayFromMediaId(
        mediaId = previousItem?.mediaId,
        extras = previousItem?.extras
      )
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToPrevious"))
    }
  }

  override fun onSeekTo(pos: Long) {
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.seekTo(pos)

      updateState(
        if (mediaPlayer.isPlaying()) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
        pos
      )

      if (mediaPlayer.isPlaying()) {
        handler.removeCallbacks(updatePlaybackPositionRunnable)
        handler.post(updatePlaybackPositionRunnable)
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "seekTo").put("value", pos))
    }
  }

  override fun onSkipToQueueItem(id: Long) {
    if(!mediaPlayer.isPreparing()) {
      val nextItem = QueueManager.getItem(mediaSession, id)
      if(nextItem != null) {
        onPlayFromMediaId(
          mediaId = nextItem.description.mediaId,
          extras = nextItem.description.extras
        )
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToQueueItem"))
    }
  }

  private fun storeLocalData(extras: Bundle, trackId: String?) {
    if(mediaSession.controller.queue !== null) {
      val stringQueue = mediaSession.controller.queue.map { it ->
        "{ \"data\":" + it.description.extras?.getString("track") + " }"
      }
      val playlistData = extras.getString("parentData")
      LocalStorageUtils.storeInFile(context, QUEUE_ITEMS_KEY, stringQueue.toString())
      LocalStorageUtils.storeInFile(context, PLAYLIST_DATA, playlistData)
      LocalStorageUtils.storeDataInPrefs(context, CURRENT_TRACK_KEY, "\"$trackId\"")

      CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE)
    }
  }

  private fun updateState(
    state: Int,
    position: Long = mediaPlayer.currentPosition
  ) {
    Log.i(TAG, "[MediaSessionCallback] Update state $state")
    val actions = (
      PlaybackStateCompat.ACTION_PLAY or
        PlaybackStateCompat.ACTION_PAUSE or
        PlaybackStateCompat.ACTION_PLAY_PAUSE or
        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
        PlaybackStateCompat.ACTION_SEEK_TO or
        PlaybackStateCompat.ACTION_SKIP_TO_QUEUE_ITEM or
        PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE
      )
    val pb = PlaybackStateCompat.Builder()
      .setActions(actions)
      .setState(state, position, 1f)
      .build()
    mediaSession.setPlaybackState(pb)
  }

  private fun handlePrepare() {
    Log.i(TAG, "[MediaSessionCallbacks] handling prepare.")
    if(mediaPlayer.currentTrackFromApp) {
      mediaPlayer.currentTrackFromApp = false
      updateState(PlaybackStateCompat.STATE_STOPPED, mediaPlayer.currentPosition)
    } else {
      mediaPlayer.start()
      updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
      handler.post(updatePlaybackPositionRunnable)
      mediaSession.isActive = true
    }
  }

  private fun handleError(what: Int, extra: Int) {
    var userFacingMessage = "An unknown error occurred during playback."
    val logMessage = StringBuilder("MediaPlayer Error: ")
    var shouldRecreatePlayer = false

    when (what) {
      MediaPlayer.MEDIA_ERROR_UNKNOWN -> {
        logMessage.append("UNKNOWN_ERROR")
        when (extra) {
          MediaPlayer.MEDIA_ERROR_IO -> {
            userFacingMessage = "Could not load the track. Please check your internet connection or try again."
            logMessage.append(" (IO Error - Network/File issue)")
          }
          MediaPlayer.MEDIA_ERROR_MALFORMED -> {
            userFacingMessage = "The track is corrupted or not in a recognizable format."
            logMessage.append(" (Malformed Media)")
          }
          MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> {
            userFacingMessage = "This media format is not supported."
            logMessage.append(" (Unsupported Media)")
          }
          MediaPlayer.MEDIA_ERROR_TIMED_OUT -> {
            userFacingMessage = "Playback timed out. Check your connection."
            logMessage.append(" (Timed Out)")
          }
          else -> {
            userFacingMessage = "An unexpected error occurred."
            logMessage.append(" (Extra: $extra)")
          }
        }
      }
      MediaPlayer.MEDIA_ERROR_SERVER_DIED -> {
        userFacingMessage = "The media playback system encountered a critical error. Please restart the app."
        logMessage.append("SERVER_DIED - Critical error, player needs full re-initialization.")
        shouldRecreatePlayer = true
      }
      else -> {
        userFacingMessage = "Playback failed. Please try a different track."
        logMessage.append(" (What: $what, Extra: $extra)")
      }
    }

    Log.e(TAG, logMessage.toString())

    // 1. Stop periodic position updates immediately
    handler.removeCallbacks(updatePlaybackPositionRunnable)

    // 2. Manage MediaPlayer state
    try {
      mediaPlayer.stop() // Stop any current playback
      if (shouldRecreatePlayer) {
        mediaPlayer.release()
      } else {
        mediaPlayer.reset() // Reset to Idle for reuse
      }
    } catch (e: IllegalStateException) {
      Log.e("MyPlaybackService", "Error during player cleanup after error: ${e.message}")
      // Fallback to full release if reset fails
      mediaPlayer.release()
    }

    // 3. Update MediaSessionCompat state to ERROR
    // Crucial to inform external controllers about the problem
    val errorMessageState = PlaybackStateCompat.Builder()
      .setState(PlaybackStateCompat.STATE_ERROR, 0, 1.0f)
      .setErrorMessage(PlaybackStateCompat.ERROR_CODE_UNKNOWN_ERROR, userFacingMessage) // Provide user-friendly message
      .setActions(0) // No actions available when in error state
      .build()
    mediaSession.setPlaybackState(errorMessageState)


    // 4. (Optional) Inform the user in the main UI
    // You'd typically use a broadcast or EventBus to send this message to your Activity/Fragment
    // Example (requires LocalBroadcastManager setup or similar):
    // val errorIntent = Intent("my_app.playback_error")
    // errorIntent.putExtra("message", userFacingMessage)
    // LocalBroadcastManager.getInstance(applicationContext).sendBroadcast(errorIntent)

    // 5. (Optional) Implement recovery logic
    // For example, if you have a playlist and the current track failed,
    // you might try to skip to the next one automatically.
    // For this, you would need to manage your playlist index.
    // skipToNextTrackIfAvailable() // Your custom function
  }

  private fun handlePlaybackCompletion() {
    Log.i(TAG, "[MediaSessionCallbacks] Media playback completed.")

    mediaPlayer.stop()
    mediaPlayer.reset()
    updateState(PlaybackStateCompat.STATE_STOPPED, 0)
    handler.removeCallbacks(updatePlaybackPositionRunnable)

    onSkipToNext()
  }

  private val updatePlaybackPositionRunnable: Runnable = object : Runnable {
    override fun run() {
      try {
        if (mediaPlayer.isPlaying()) {
          Log.i(TAG, "[MediaSessionCallback] Update Playback position, player is playing")
          val currentPosition = mediaPlayer.currentPosition
          val currentState =
            PlaybackStateCompat.STATE_PLAYING

          updateState(currentState, currentPosition)
        }
        handler.postDelayed(this, PLAYBACK_POSITION_UPDATE_INTERVAL)
      } catch (e: Exception) {
        // Prevent app to break when disconnected.
      }

    }
  }
}

