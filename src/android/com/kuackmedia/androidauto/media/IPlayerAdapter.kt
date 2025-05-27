package com.kuackmedia.androidauto.media

import android.support.v4.media.MediaBrowserCompat


/**
 * Abstracts your playback engine (MediaPlayer, ExoPlayer, etc.).
 */
interface IPlayerAdapter {
  fun play()
  fun pause()
  fun skipToNext()
  fun skipToPrevious()
  fun seekTo(position: Long)
  fun setCurrentTrack(track: String)
  val currentPosition: Long
}

