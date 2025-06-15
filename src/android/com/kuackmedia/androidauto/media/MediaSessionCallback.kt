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
  var currentQueueIndex = 0

  override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
    Log.i(TAG, "[onPlayFromMediaId] Start $mediaId")
    val id = mediaId ?: return
    
    // Check if this is a hardcoded track
    if (id.contains("hardcoded_")) {
      // This is a hardcoded track, use the media_uri from extras directly
      val trackUrl = extras?.getString("media_uri")
      if (trackUrl != null) {
        Log.i(TAG, "[onPlayFromMediaId] Playing hardcoded track: $trackUrl")
        mediaPlayer.setCurrentTrack(Uri.parse(trackUrl))
        mediaPlayer.playCurrentTrack(context)
        updateState(PlaybackStateCompat.STATE_PLAYING)
        
        val metadata = MediaMetadataCompat.Builder()
          .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras.getString("title"))
          .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras.getString("artist"))
          .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras.getString("album"))
          .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
          .build()
          
        mediaSession.setMetadata(metadata)
      } else {
        Log.e(TAG, "[onPlayFromMediaId] No media_uri found in extras for hardcoded track")
      }
      return
    }
    
    // Handle regular tracks from the API
    val dataMediaId = id.split("_").last()
    Log.i(TAG, "[onPlayFromMediaId] dataMediaId $dataMediaId")

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val trackUrl: Uri? = LocalStorageUtils.getTrackUri(context, dataMediaId)
        withContext(Dispatchers.Main) {
          Log.i(TAG, "[onPlayFromMediaId] Current track $trackUrl")
          mediaPlayer.setCurrentTrack(trackUrl)
          mediaPlayer.playCurrentTrack(context)
          updateState(PlaybackStateCompat.STATE_PLAYING)

          val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras?.getString("title"))
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras?.getString("artist"))
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras?.getString("album"))
            .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, extras?.getString("image"))
            .build()

          mediaSession.setMetadata(metadata)
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

  override fun onStop() {
    mediaPlayer.stop()
    mediaPlayer.seekTo(0)

    mediaSession.isActive = false

    updateState(PlaybackStateCompat.STATE_STOPPED)
  }

  override fun onPause() {
    mediaPlayer.pause()
    updateState(PlaybackStateCompat.STATE_PAUSED)
  }

  override fun onSkipToNext() {
    val nextItem = getNextQueueItem()?.description
    onPlayFromMediaId(
      mediaId = nextItem?.mediaId,
      extras = nextItem?.extras
    )
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

  override fun onSkipToPrevious() {
    val previousItem = getPreviousQueueItem()?.description
    onPlayFromMediaId(
      mediaId = previousItem?.mediaId,
      extras = previousItem?.extras
    )
    updateState(PlaybackStateCompat.STATE_PLAYING)
  }

//  override fun onSeekTo(pos: Long) {
//    mediaPlayer.seekTo(pos)
//    updateState(PlaybackStateCompat.STATE_PLAYING, pos)
//  }

  override fun onSkipToQueueItem(id: Long) {
    val nextItemUri = mediaSession.controller.queue[id.toInt()].description
    if(nextItemUri != null) {
      onPlayFromMediaId(
        mediaId = nextItemUri.mediaId,
        extras = nextItemUri.extras
      )
      currentQueueIndex = id.toInt()
      updateState(PlaybackStateCompat.STATE_PLAYING)
    }
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

  fun getNextQueueItem(): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    return if (queue != null && currentQueueIndex + 1 < queue.size) {
      currentQueueIndex += 1
      queue[currentQueueIndex]
    } else {
      null
    }
  }

  fun getPreviousQueueItem(): MediaSessionCompat.QueueItem? {
    val queue = mediaSession.controller.queue
    return if (queue != null && currentQueueIndex - 1 > 0) {
      currentQueueIndex -= 1
      queue[currentQueueIndex]
    } else {
      null
    }
  }
}

