package com.kuackmedia.androidauto.media

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.util.Log


/**
 * A simple PlayerAdapter that wraps Android's MediaPlayer.
 */
class MediaPlayerAdapter() : IPlayerAdapter {

  private val TAG = "MediaPlayerAdapter"
  private val mediaPlayer = MediaPlayer()
  private var currentTrackUri: Uri? = null

  override val currentPosition: Long
    get() = mediaPlayer.currentPosition.toLong()

  init {
    Log.i(TAG, "MediaPlayerAdapter init")
    mediaPlayer.setAudioAttributes(
      AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    )
    mediaPlayer.setOnErrorListener { mp, what, extra ->
      Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")
      true
    }

    mediaPlayer.setOnInfoListener { mp, what, extra ->
      Log.i(TAG, "MediaPlayer info: what=$what, extra=$extra")
      false
    }

    mediaPlayer.setOnPreparedListener { mp ->
      {
        Log.i(TAG, "[playCurrentTrack] Starting player")
        mp?.start()
      }
    }
  }

  override fun listenOnTrackFinished(callback: () -> Unit) {
    mediaPlayer.setOnCompletionListener {
      callback()
    }
  }

  override fun play() {
    Log.i(TAG, "[MediaPlayerAdapter] Play was executed")
    if (mediaPlayer.isPlaying) {
      mediaPlayer.stop()
      mediaPlayer.reset()
    }
    mediaPlayer.start()
  }

  override fun playCurrentTrack(context: Context) {
    try {
      if (mediaPlayer.isPlaying) {
        mediaPlayer.stop()
        mediaPlayer.reset()
      }

      if (this.currentTrackUri != null) {
        mediaPlayer.reset()

        val url = this.currentTrackUri.toString()

        mediaPlayer.run {
          Log.i(TAG, "[playCurrentTrack] Setting data source $url")
          mediaPlayer.setDataSource(url)
          mediaPlayer.prepareAsync()
          Log.i(TAG, "[playCurrentTrack] Prepare was completed")
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
    mediaPlayer.seekTo(position.toInt())
    mediaPlayer.start()
  }

  override fun setCurrentTrack(trackUri: Uri?){
    this.currentTrackUri = trackUri
  }

  /** Release when your service is destroyed */
  override fun release() {
    Log.i(TAG, "[MediaPlayerAdapter] Release was executed")
    mediaPlayer.release()
  }
}

