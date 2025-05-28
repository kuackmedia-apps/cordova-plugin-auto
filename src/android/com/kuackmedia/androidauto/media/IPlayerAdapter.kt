package com.kuackmedia.androidauto.media

import android.content.Context
import android.net.Uri


/**
 * Abstracts your playback engine (MediaPlayer, ExoPlayer, etc.).
 */
interface IPlayerAdapter {
  fun play()
  fun playCurrentTrack(context: Context)
  fun pause()
  fun stop()
  fun listenOnTrackFinished(callback: () -> Unit)
  fun seekTo(position: Long)
  fun setCurrentTrack(track: Uri?)
  fun release()
  val currentPosition: Long
}

