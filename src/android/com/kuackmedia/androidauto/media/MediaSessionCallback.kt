package com.kuackmedia.androidauto.media

import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

/**
 * Routes transport controls to your PlayerAdapter and
 * keeps the session’s PlaybackState in sync.
 */
class MediaSessionCallback(
  private val player: IPlayerAdapter,
  private val session: MediaSessionCompat
) : MediaSessionCompat.Callback() {

  override fun onPlay() {
    player.play()
    updateState(PlaybackStateCompat.STATE_PLAYING)
    session.isActive = true
  }

  override fun onPause() {
    player.pause()
    updateState(PlaybackStateCompat.STATE_PAUSED)
  }

  override fun onSkipToNext() {
    player.skipToNext()
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  override fun onSkipToPrevious() {
    player.skipToPrevious()
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  override fun onSeekTo(pos: Long) {
    player.seekTo(pos)
    updateState(PlaybackStateCompat.STATE_PLAYING, pos)
  }

  override fun onSkipToQueueItem(id: Long) {
    player.skipToNext()
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  private fun updateState(
    state: Int,
    position: Long = player.currentPosition
  ) {
    val actions = (
      PlaybackStateCompat.ACTION_PLAY or
        PlaybackStateCompat.ACTION_PAUSE or
        PlaybackStateCompat.ACTION_PLAY_PAUSE or
        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
        PlaybackStateCompat.ACTION_SEEK_TO or
        PlaybackStateCompat.ACTION_SKIP_TO_QUEUE_ITEM
      )
    val pb = PlaybackStateCompat.Builder()
      .setActions(actions)
      .setState(state, position, /* speed= */ 1f)
      .build()
    session.setPlaybackState(pb)
  }
}

