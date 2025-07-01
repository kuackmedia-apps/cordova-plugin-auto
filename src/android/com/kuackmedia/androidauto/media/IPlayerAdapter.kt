package com.kuackmedia.androidauto.media

import android.content.Context
import android.net.Uri


/**
 * Abstracts your playback engine (MediaPlayer, ExoPlayer, etc.).
 */
interface IPlayerAdapter {
  fun play()
  fun start()
  fun playCurrentTrack(context: Context)
  fun pause()
  fun stop()
  fun reset()
  fun seekTo(position: Long)
  fun setCurrentTrack(track: Uri?)
  fun release()
  fun isPlaying(): Boolean
  fun isPreparing(): Boolean
  fun setOnCompletionListener(handlePlaybackCompletion: () -> Unit)
  fun setOnPreparedListener(handlePlaybackCompletion: () -> Unit)
  fun setOnErrorListener(handleError: ( what: Int, extra: Int) -> Unit)
  val currentPosition: Long
}

