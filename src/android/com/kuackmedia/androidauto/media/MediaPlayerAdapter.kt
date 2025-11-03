package com.kuackmedia.androidauto.media

import android.content.Context
import android.content.Context.AUDIO_SERVICE
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaPlayer.OnCompletionListener
import android.media.MediaPlayer.OnPreparedListener
import android.net.Uri
import android.util.Log

/**
 * A simple PlayerAdapter that wraps Android's MediaPlayer.
 */
class MediaPlayerAdapter() : IPlayerAdapter {

  private val TAG = "MediaPlayerAdapter"
  private val mediaPlayer = MediaPlayer()
  private var currentTrackUri: Uri? = null
  private var isPreparing = false
  private var isReleased = false
  private var currentAudioFocusRequest: AudioFocusRequest? = null
  private var currentAudioManager: AudioManager? = null
  private var shouldIgnoreAudioFocusLoss = false
  private var audioFocusChangeCallback: ((Int) -> Unit)? = null

  override var currentTrackFromApp: Boolean = false

  override val currentPosition: Long
    get() = if (!isReleased && (mediaPlayer.isPlaying || isPreparing)) {
      mediaPlayer.currentPosition.toLong()
    } else {
      0L
    }

  override fun release() {
    Log.i(TAG, "[MediaPlayerAdapter] Release was executed")
    isReleased = true

    // Release audio focus before releasing the media player
    currentAudioFocusRequest?.let { request ->
      currentAudioManager?.abandonAudioFocusRequest(request)
      Log.i(TAG, "[RELEASE] Audio focus abandoned")
    }
    currentAudioFocusRequest = null
    currentAudioManager = null

    mediaPlayer.release()
  }

  override fun reset() {
    Log.i(TAG, "[MediaPlayerAdapter] Reset was executed")
    isReleased = false
    mediaPlayer.reset()
  }

  init {
    Log.i(TAG, "MediaPlayerAdapter init")
    mediaPlayer.setAudioAttributes(
      AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    )

    mediaPlayer.isLooping = false
  }

  override fun setOnErrorListener(handleError: ( what: Int, extra: Int) -> Unit) {
   mediaPlayer.setOnErrorListener(object : MediaPlayer.OnErrorListener {
     override fun onError(mp: MediaPlayer?, what: Int, extra: Int): Boolean {
       handleError(what, extra)
       isPreparing = false
       return true
     }
   })
  }

  override fun setOnAudioFocusChangeListener(callback: (Int) -> Unit) {
    this.audioFocusChangeCallback = callback
    Log.i(TAG, "[SET_AUDIO_FOCUS_LISTENER] Audio focus change callback registered")
  }

  override fun setOnCompletionListener(handlePlaybackCompletion: () -> Unit) {
    mediaPlayer.setOnCompletionListener(object : OnCompletionListener {
      override fun onCompletion(mp: MediaPlayer?) {
        Log.i(TAG, "[MediaPlayerAdapter] Finished track")
        handlePlaybackCompletion()
      }
    })
  }

  override fun setOnPreparedListener(handlePrepare: () -> Unit) {
    mediaPlayer.setOnPreparedListener(object : OnPreparedListener {
      override fun onPrepared(mp: MediaPlayer?) {
        Log.i(TAG, "[PREPARE_CALLBACK] Prepare callback called")
        handlePrepare()
        isPreparing = false

        // After preparation is complete and playback has started,
        // wait a bit before allowing audio focus loss to pause playback
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
          shouldIgnoreAudioFocusLoss = false
          Log.i(TAG, "[PREPARE_CALLBACK] Audio focus loss handling re-enabled")
        }, 500)
      }
    })
  }

  override fun isPlaying(): Boolean {
    return this.mediaPlayer.isPlaying
  }

  override fun isPreparing(): Boolean {
    return this.isPreparing
  }

  override fun start() {
    Log.i(TAG, "[START] start() called, isPreparing: $isPreparing, isPlaying: ${mediaPlayer.isPlaying}")
    try {
      mediaPlayer.start()
      Log.i(TAG, "[START_SUCCESS] mediaPlayer.start() completed, isPlaying: ${mediaPlayer.isPlaying}")
    } catch (e: Exception) {
      Log.e(TAG, "[START_ERROR] Error calling mediaPlayer.start(): ${e.message}", e)
    }
  }

  override fun play() {
    if (mediaPlayer.isPlaying) {
      mediaPlayer.stop()
      mediaPlayer.reset()
    }
    if(!isPreparing) mediaPlayer.start()
  }

  override fun playCurrentTrack(context: Context) {
    try {
      Log.i(TAG, "[PLAY_TRACK_START] Starting playback for URI: ${this.currentTrackUri}")

      val audioManager = context.getSystemService(AUDIO_SERVICE) as AudioManager
      this.currentAudioManager = audioManager

      // Create the focus request but DON'T request focus yet
      // We'll request it in handlePrepare() when the player is actually ready
      val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        )
        .setAcceptsDelayedFocusGain(true)
        .setWillPauseWhenDucked(false)
        .setOnAudioFocusChangeListener { focusChange ->
          Log.i(TAG, "[AUDIO_FOCUS_CHANGE] Audio focus changed to: $focusChange, shouldIgnoreAudioFocusLoss: $shouldIgnoreAudioFocusLoss")

          when (focusChange) {
            AudioManager.AUDIOFOCUS_GAIN -> {
              Log.i(TAG, "[AUDIO_FOCUS_GAIN] Gained audio focus")
              // Always notify about GAIN events
              audioFocusChangeCallback?.invoke(focusChange)
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
              if (shouldIgnoreAudioFocusLoss) {
                Log.w(TAG, "[AUDIO_FOCUS_LOSS] Lost audio focus permanently, but IGNORING due to shouldIgnoreAudioFocusLoss flag")
              } else {
                Log.w(TAG, "[AUDIO_FOCUS_LOSS] Lost audio focus permanently")
                // Notify the callback (MediaSessionCallback) about the focus change
                audioFocusChangeCallback?.invoke(focusChange)
              }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
              if (shouldIgnoreAudioFocusLoss) {
                Log.w(TAG, "[AUDIO_FOCUS_LOSS_TRANSIENT] Lost audio focus temporarily, but IGNORING due to shouldIgnoreAudioFocusLoss flag")
              } else {
                Log.w(TAG, "[AUDIO_FOCUS_LOSS_TRANSIENT] Lost audio focus temporarily")
                audioFocusChangeCallback?.invoke(focusChange)
              }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
              if (shouldIgnoreAudioFocusLoss) {
                Log.w(TAG, "[AUDIO_FOCUS_LOSS_TRANSIENT_DUCK] Lost audio focus, can duck, but IGNORING due to shouldIgnoreAudioFocusLoss flag")
              } else {
                Log.w(TAG, "[AUDIO_FOCUS_LOSS_TRANSIENT_DUCK] Lost audio focus, can duck")
                audioFocusChangeCallback?.invoke(focusChange)
              }
            }
            else -> {
              Log.w(TAG, "[AUDIO_FOCUS_UNKNOWN] Unknown audio focus change: $focusChange")
              audioFocusChangeCallback?.invoke(focusChange)
            }
          }
        }
        .build()

      this.currentAudioFocusRequest = focusRequest
      Log.i(TAG, "[PLAY_TRACK_FOCUS_REQUEST_CREATED] Audio focus request created, will request in handlePrepare()")

      if (mediaPlayer.isPlaying) {
        Log.d(TAG, "[PLAY_TRACK_STOP] Stopping current playback")
        mediaPlayer.stop()
        mediaPlayer.reset()
      }

      if (this.currentTrackUri != null) {
        Log.d(TAG, "[PLAY_TRACK_RESET] Resetting media player")
        mediaPlayer.reset()

        val uriString = this.currentTrackUri.toString()
        val uriScheme = this.currentTrackUri?.scheme

        Log.i(TAG, "[PLAY_TRACK_URI_INFO] URI scheme: $uriScheme, full URI: $uriString")
        Log.i(TAG, "[PLAY_TRACK_SET_SOURCE] Setting data source")

        // Check if it's a file:// URI and use alternative method
        if (uriScheme == "file") {
          Log.i(TAG, "[PLAY_TRACK_FILE_URI] Detected file:// URI, using setDataSource with context")
          try {
            mediaPlayer.setDataSource(context, this.currentTrackUri!!)
            Log.i(TAG, "[PLAY_TRACK_FILE_URI_SUCCESS] setDataSource with context succeeded")
          } catch (e: Exception) {
            Log.e(TAG, "[PLAY_TRACK_FILE_URI_ERROR] setDataSource with context failed: ${e.message}", e)
            Log.i(TAG, "[PLAY_TRACK_FILE_URI_FALLBACK] Trying string-based setDataSource")
            mediaPlayer.setDataSource(uriString)
          }
        } else {
          Log.i(TAG, "[PLAY_TRACK_REMOTE_URI] Using string-based setDataSource for remote URI")
          mediaPlayer.setDataSource(uriString)
        }

        Log.i(TAG, "[PLAY_TRACK_PREPARE] Starting async prepare")
        mediaPlayer.prepareAsync()
        isPreparing = true
        Log.i(TAG, "[PLAY_TRACK_PREPARING] isPreparing set to true")
      } else {
        Log.w(TAG, "[PLAY_TRACK_NO_URI] currentTrackUri is null, cannot play")
      }
    } catch (e: Exception) {
      Log.e(TAG, "[PLAY_TRACK_ERROR] Error in playTrack: ${e.message}", e)
      Log.e(TAG, "[PLAY_TRACK_STACK_TRACE] ${e.stackTraceToString()}")
      isPreparing = false
    }
  }

  override fun pause() {
    Log.i(TAG, "[MediaPlayerAdapter] Pause was executed")
    if (mediaPlayer.isPlaying) {
      mediaPlayer.pause()
    }
  }

  override fun stop() {
    Log.i(TAG, "[MediaPlayerAdapter] Stop was executed")
    if (mediaPlayer.isPlaying) {
      mediaPlayer.stop()
    }
  }

  override fun seekTo(position: Long) {
    Log.i(TAG, "Seek to $position isPreparing $isPreparing")
    if(!isPreparing) {
      mediaPlayer.seekTo(position.toInt())
      mediaPlayer.start()
    }
  }

  override fun setCurrentTrack(trackUri: Uri?){
    this.currentTrackUri = trackUri
  }

  override fun requestAudioFocusForPlayback(): Boolean {
    Log.i(TAG, "[REQUEST_AUDIO_FOCUS] Requesting audio focus for playback")
    currentAudioFocusRequest?.let { request ->
      currentAudioManager?.let { manager ->
        // Enable the ignore flag BEFORE requesting focus to prevent immediate loss handling
        shouldIgnoreAudioFocusLoss = true
        Log.i(TAG, "[REQUEST_AUDIO_FOCUS] Enabled shouldIgnoreAudioFocusLoss flag")

        val result = manager.requestAudioFocus(request)
        Log.i(TAG, "[REQUEST_AUDIO_FOCUS_RESULT] Audio focus request result: $result")

        val granted = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!granted) {
          // If we didn't get focus, disable the ignore flag
          shouldIgnoreAudioFocusLoss = false
          Log.w(TAG, "[REQUEST_AUDIO_FOCUS] Focus not granted, disabled shouldIgnoreAudioFocusLoss flag")
        }
        return granted
      }
    }
    Log.w(TAG, "[REQUEST_AUDIO_FOCUS_FAILED] No audio manager or focus request available")
    return false
  }

  override fun shouldIgnorePauseCommands(): Boolean {
    return shouldIgnoreAudioFocusLoss
  }
}

