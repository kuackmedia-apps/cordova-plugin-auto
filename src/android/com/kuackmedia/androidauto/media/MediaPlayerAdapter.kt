package com.kuackmedia.androidauto.media

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.support.v4.media.MediaBrowserCompat


/**
 * A simple PlayerAdapter that wraps Android's MediaPlayer.
 */
class MediaPlayerAdapter(service: MusicLibraryService) : IPlayerAdapter {

  private val mediaPlayer = MediaPlayer()
  private val playlist = mutableListOf<String>()
  private var currentIndex = 0

  override val currentPosition: Long
    get() = mediaPlayer.currentPosition.toLong()

  init {
    mediaPlayer.setAudioAttributes(
      AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    )
    mediaPlayer.setOnCompletionListener {
      // auto-advance when a track finishes
      skipToNext()
    }
  }

  override fun play() {
    if (!mediaPlayer.isPlaying) {
      mediaPlayer.start()
    }
  }

  override fun pause() {
    if (mediaPlayer.isPlaying) {
      mediaPlayer.pause()
    }
  }

  override fun skipToNext() {
    if (playlist.isEmpty()) return
    currentIndex = (currentIndex + 1) % playlist.size
    mediaPlayer.reset()
    mediaPlayer.setDataSource(playlist[currentIndex])
    mediaPlayer.prepare()  // or prepareAsync() with a listener
    mediaPlayer.start()
  }

  override fun skipToPrevious() {
    if (playlist.isEmpty()) return
    currentIndex = if (currentIndex == 0) playlist.lastIndex else currentIndex - 1
    mediaPlayer.reset()
    mediaPlayer.setDataSource(playlist[currentIndex])
    mediaPlayer.prepare()
    mediaPlayer.start()
  }

  override fun seekTo(position: Long) {
    mediaPlayer.seekTo(position.toInt())
  }

  override fun setCurrentTrack(trackUri: String){
    mediaPlayer.reset()
    mediaPlayer.setDataSource(trackUri);
    mediaPlayer.prepareAsync();
  }

  /** Release when your service is destroyed */
  fun release() {
    mediaPlayer.release()
  }
}

