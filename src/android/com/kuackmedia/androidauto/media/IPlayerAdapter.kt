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
  fun setOnAudioFocusChangeListener(callback: (Int) -> Unit)
  fun requestAudioFocusForPlayback(): Boolean
  // true si el último requestAudioFocusForPlayback quedó en AUDIOFOCUS_REQUEST_DELAYED (p. ej. durante una llamada):
  // el foco llega más tarde con un AUDIOFOCUS_GAIN.
  val lastFocusRequestDelayed: Boolean
  // true entre onPrepared y el próximo reset/stop/release/error: start() es válido (sin MEDIA_ERROR -38).
  val isPrepared: Boolean
  fun shouldIgnorePauseCommands(): Boolean
  val currentPosition: Long
  var currentTrackFromApp: Boolean
  var shouldAutoPlayOnPrepare: Boolean
}

