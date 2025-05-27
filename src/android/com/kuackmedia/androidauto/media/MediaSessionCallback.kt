package com.kuackmedia.androidauto.media

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import com.kuackmedia.androidauto.utils.LocalStorageUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Routes transport controls to your PlayerAdapter and
 * keeps the session’s PlaybackState in sync.
 */
class MediaSessionCallback(
  private val mediaPlayer: IPlayerAdapter,
  private val mediaSession: MediaSessionCompat,
  private val context: Context
) : MediaSessionCompat.Callback() {
  val TAG = "MediaSessionCallback"

  override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
    Log.i(TAG, "[onPlayFromMediaId] Start $mediaId")
    val id = mediaId ?: return
    val dataMediaId = id.split("_").last()
    Log.i(TAG, "[onPlayFromMediaId] dataMediaId $dataMediaId")

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val trackUrl: Uri? = LocalStorageUtils.getTrackUri(context, dataMediaId)
        withContext(Dispatchers.Main) {
          playTrack(id, trackUrl)
        }
      } catch (e: Exception) {
        Log.e("MediaSession", "Failed to load track URI", e)
      }
    }
  }

  override fun onPlay() {
    mediaPlayer.play()
    updateState(PlaybackStateCompat.STATE_PLAYING)
    mediaSession.isActive = true
  }

  override fun onPause() {
    mediaPlayer.pause()
    updateState(PlaybackStateCompat.STATE_PAUSED)
  }

  override fun onSkipToNext() {
    mediaPlayer.skipToNext()
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  override fun onSkipToPrevious() {
    mediaPlayer.skipToPrevious()
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  override fun onSeekTo(pos: Long) {
    mediaPlayer.seekTo(pos)
    updateState(PlaybackStateCompat.STATE_PLAYING, pos)
  }

  override fun onSkipToQueueItem(id: Long) {
    mediaPlayer.skipToNext()
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  private fun updateState(
    state: Int,
    position: Long = mediaPlayer.currentPosition
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
    mediaSession.setPlaybackState(pb)
  }

  fun playTrack(mediaId: String, url: Uri?) {
    val metadata = MediaMetadataCompat.Builder()
      .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
      .putString(MediaMetadataCompat.METADATA_KEY_TITLE, "Track $mediaId")
      .build()

    mediaSession.setMetadata(metadata)

    try {
      mediaPlayer.setCurrentTrack(url.toString())
      mediaPlayer.play()
    } catch (e: Exception) {
      Log.e("MediaPlayer", "Playback error", e)
    }

    mediaSession.setPlaybackState(
      PlaybackStateCompat.Builder()
        .setState(PlaybackStateCompat.STATE_PLAYING, 0L, 1f)
        .build()
    )
  }
}

