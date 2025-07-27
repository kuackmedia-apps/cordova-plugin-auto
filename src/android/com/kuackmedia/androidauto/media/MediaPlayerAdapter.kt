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

  override var currentTrackFromApp: Boolean = false

  override val currentPosition: Long
    get() = if (mediaPlayer.isPlaying || isPreparing) {
      mediaPlayer.currentPosition.toLong()
    } else {
      0L
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
        Log.i(TAG, "[MediaPlayerAdapter] Prepare callback called")
        handlePrepare()
        isPreparing = false
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
    mediaPlayer.start()
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
      val audioManager = context.getSystemService(AUDIO_SERVICE) as AudioManager
      val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        )
        .setOnAudioFocusChangeListener { /* react to changes */ }
        .build()

      val result = audioManager.requestAudioFocus(focusRequest)

      if (mediaPlayer.isPlaying) {
        mediaPlayer.stop()
        mediaPlayer.reset()
      }

      if (this.currentTrackUri != null) {
        mediaPlayer.reset()

        val url = this.currentTrackUri.toString()

        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
          Log.i(TAG, "[playCurrentTrack] Setting data source $url")
          mediaPlayer.setDataSource(url)
          mediaPlayer.prepareAsync()
          isPreparing = true
        }

      }
    } catch (e: Exception) {
      Log.e(TAG, "Error en playTrack", e)
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

  /** Release when your service is destroyed */
  override fun release() {
    Log.i(TAG, "[MediaPlayerAdapter] Release was executed")
    mediaPlayer.release()
  }

  override fun reset() {
    Log.i(TAG, "[MediaPlayerAdapter] Reset was executed")
    mediaPlayer.reset()
  }
}

