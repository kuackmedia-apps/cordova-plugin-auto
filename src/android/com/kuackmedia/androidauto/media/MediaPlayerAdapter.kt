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
  override var shouldAutoPlayOnPrepare: Boolean = false

  override val currentPosition: Long
    get() = if (!isReleased && (mediaPlayer.isPlaying || isPreparing)) {
      mediaPlayer.currentPosition.toLong()
    } else {
      0L
    }

  override fun release() {
    isReleased = true

    // Release audio focus before releasing the media player
    currentAudioFocusRequest?.let { request ->
      currentAudioManager?.abandonAudioFocusRequest(request)
    }
    currentAudioFocusRequest = null
    currentAudioManager = null

    mediaPlayer.release()
  }

  override fun reset() {
    isReleased = false
    mediaPlayer.reset()
  }

  init {
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
  }

  override fun setOnCompletionListener(handlePlaybackCompletion: () -> Unit) {
    mediaPlayer.setOnCompletionListener(object : OnCompletionListener {
      override fun onCompletion(mp: MediaPlayer?) {
        handlePlaybackCompletion()
      }
    })
  }

  override fun setOnPreparedListener(handlePrepare: () -> Unit) {
    mediaPlayer.setOnPreparedListener(object : OnPreparedListener {
      override fun onPrepared(mp: MediaPlayer?) {
        handlePrepare()
        isPreparing = false

        // After preparation is complete and playback has started,
        // wait a bit before allowing audio focus loss to pause playback
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
          shouldIgnoreAudioFocusLoss = false
        }, 500)
      }
    })
  }

  override fun isPlaying(): Boolean {
    // Check if player is released before calling isPlaying()
    // to avoid IllegalStateException
    if (isReleased) {
      return false
    }
    return try {
      this.mediaPlayer.isPlaying
    } catch (e: IllegalStateException) {
      Log.w(TAG, "[IS_PLAYING] IllegalStateException caught, player in invalid state: ${e.message}")
      false
    }
  }

  override fun isPreparing(): Boolean {
    return this.isPreparing
  }

  override fun start() {
    try {
      mediaPlayer.start()

      // Verify the player is actually outputting audio
      if (!mediaPlayer.isPlaying) {
        Log.w(TAG, "[START_WARNING] start() called but isPlaying is false!")
      }
    } catch (e: Exception) {
      Log.e(TAG, "[START_ERROR] Error calling mediaPlayer.start(): ${e.message}", e)
    }
  }

  override fun play() {
    try {
      if (!isPreparing && !mediaPlayer.isPlaying) {
        mediaPlayer.start()

        // After playback has started, wait a bit before allowing audio focus loss/pause commands
        // This prevents race conditions with audio focus
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
          shouldIgnoreAudioFocusLoss = false
        }, 500)
      }
    } catch (e: Exception) {
      Log.e(TAG, "[PLAY_ERROR] Error calling mediaPlayer.start(): ${e.message}", e)
    }
  }

  override fun playCurrentTrack(context: Context) {
    try {
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
          when (focusChange) {
            AudioManager.AUDIOFOCUS_GAIN -> {
              // Always notify about GAIN events
              audioFocusChangeCallback?.invoke(focusChange)
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
              if (!shouldIgnoreAudioFocusLoss) {
                // Notify the callback (MediaSessionCallback) about the focus change
                audioFocusChangeCallback?.invoke(focusChange)
              }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
              if (!shouldIgnoreAudioFocusLoss) {
                audioFocusChangeCallback?.invoke(focusChange)
              }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
              if (!shouldIgnoreAudioFocusLoss) {
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

      if (mediaPlayer.isPlaying) {
        mediaPlayer.stop()
        mediaPlayer.reset()
      }

      if (this.currentTrackUri != null) {
        mediaPlayer.reset()

        val uriString = this.currentTrackUri.toString()
        val uriScheme = this.currentTrackUri?.scheme

        // Check if it's a file:// URI and use alternative method
        if (uriScheme == "file") {
          try {
            mediaPlayer.setDataSource(context, this.currentTrackUri!!)
          } catch (e: Exception) {
            Log.e(TAG, "[PLAY_TRACK_FILE_URI_ERROR] setDataSource with context failed: ${e.message}", e)
            mediaPlayer.setDataSource(uriString)
          }
        } else {
          mediaPlayer.setDataSource(uriString)
        }

        mediaPlayer.prepareAsync()
        isPreparing = true
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
    if (mediaPlayer.isPlaying) {
      mediaPlayer.pause()
    }
  }

  override fun stop() {
    if (mediaPlayer.isPlaying) {
      mediaPlayer.stop()
    }
  }

  override fun seekTo(position: Long) {
    if(!isPreparing) {
      mediaPlayer.seekTo(position.toInt())
    }
  }

  override fun setCurrentTrack(trackUri: Uri?){
    this.currentTrackUri = trackUri
  }

  override fun requestAudioFocusForPlayback(): Boolean {
    currentAudioFocusRequest?.let { request ->
      currentAudioManager?.let { manager ->
        // Enable the ignore flag BEFORE requesting focus to prevent immediate loss handling
        shouldIgnoreAudioFocusLoss = true

        val result = manager.requestAudioFocus(request)

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

