package com.kuackmedia.androidauto.media

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Context.MODE_PRIVATE
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.media.session.MediaButtonReceiver
import com.kuackmedia.androidauto.CordovaEventBridge
import com.kuackmedia.androidauto.CordovaEvents
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.CURRENT_TRACK_KEY
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.QUEUE_ITEMS_KEY
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.PLAYLIST_DATA
import com.kuackmedia.androidauto.tree.MediaItemTree
import com.kuackmedia.androidauto.utils.LocalStorageUtils
import com.kuackmedia.androidauto.utils.MediaUtils
import org.json.JSONObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL
import kotlin.or
import kotlin.toString


/**
 * Routes transport controls to your PlayerAdapter and
 * keeps the session’s PlaybackState in sync.
 */
class MediaSessionCallback(
  private val mediaPlayer: IPlayerAdapter,
  private val mediaSession: MediaSessionCompat,
  private val context: Context
) : MediaSessionCompat.Callback() {

  companion object {
    private const val PLAYBACK_POSITION_UPDATE_INTERVAL: Long = 1000
    private const val TAG = "MediaSessionCallback"
    private const val NOTIFICATION_ID = 1
    private const val CHANNEL_ID = "media_playback_channel"
  }

  private val handler: Handler = Handler(Looper.getMainLooper())
  private var currentQueue: List<MediaSessionCompat.QueueItem>? = null
  private var currentTrack: MediaBrowserCompat.MediaItem? = null
  private var isCalledFromOnPrepare: Boolean = false

  init {
    // This executes when a track ends playing
    mediaPlayer.setOnCompletionListener {
      handlePlaybackCompletion()
    }

    // This executes when the track is loaded into the player
    mediaPlayer.setOnPreparedListener {
      handlePrepare()
    }

    // This executes on error
    mediaPlayer.setOnErrorListener { what, extra ->
      handleError(what, extra)
    }

    // This executes when audio focus changes
    mediaPlayer.setOnAudioFocusChangeListener { focusChange ->
      handleAudioFocusChange(focusChange)
    }
  }

  override fun onPrepare() {
    Log.d(TAG, "[ON_PREPARE] onPrepare triggered")

    val prefs = this.context.getSharedPreferences("NativeStorage", MODE_PRIVATE)
    this.currentQueue = QueueManager.getCurrentQueue(this.context)

    if(currentQueue !== null) {
      Log.d(TAG, "[ON_PREPARE] Current queue size: ${currentQueue?.size}")
      val savedTrackId = prefs.getString(CURRENT_TRACK_KEY, null).toString().replace("\"", "")
      Log.i(TAG, "[ON_PREPARE] Saved track ID from prefs: $savedTrackId")

      this.currentTrack =
        CurrentMedia.getCurrentTrackFromQueue(
          savedTrackId,
          this.currentQueue
        )
      Log.i(TAG, "[ON_PREPARE] Current track from queue: ${this.currentTrack?.mediaId}")

      // When onPrepare is called (e.g., when Android Auto connects), we set a flag to prevent auto-play
      // This is not an explicit user action, so the track should be loaded but not played automatically
      Log.i(TAG, "[ON_PREPARE] Setting isCalledFromOnPrepare flag to prevent auto-play")
      isCalledFromOnPrepare = true

      this.onPlayFromMediaId(this.currentTrack?.mediaId, this.currentTrack?.description?.extras)
    }
  }

  override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
    val mediaSessionContext = extras?.getString("MEDIA_SESSION_SERVICE_CONTEXT")

    // Check if this call is from onPrepare()
    if (isCalledFromOnPrepare) {
      isCalledFromOnPrepare = false  // Reset flag immediately

      // Check if shouldAutoPlayOnPrepare was already set (e.g., by playCurrentTrack from app)
      if (mediaPlayer.shouldAutoPlayOnPrepare) {
        Log.i(TAG, "[onPlayFromMediaId] Called from onPrepare with auto-play flag (app request), will auto-play")
        // Keep shouldAutoPlayOnPrepare = true, it was set by playCurrentTrack()
      } else {
        Log.i(TAG, "[onPlayFromMediaId] Called from onPrepare without auto-play flag (Android Auto connection), NO auto-play")
        // This is just Android Auto connecting, not an explicit play request
        mediaPlayer.currentTrackFromApp = true  // Mark to prevent auto-play in handlePrepare
      }
    } else {
      // If this is called directly from Android Auto (not from skip methods which already set the flag),
      // then enable auto-play
      // Skip methods (onSkipToNext, onSkipToPrevious, onSkipToQueueItem) already set shouldAutoPlayOnPrepare
      if (!mediaPlayer.shouldAutoPlayOnPrepare && !mediaPlayer.currentTrackFromApp) {
        Log.i(TAG, "[onPlayFromMediaId] Direct call from Android Auto, enabling auto-play")
        mediaPlayer.shouldAutoPlayOnPrepare = true
      }
    }

    fun getDurationStringLength(length: String?, filePath: String?): Long {
      var duration: Long = 0
      if( !length.isNullOrEmpty()) {
        duration = MediaUtils.parseDuration(length)
        Log.i(TAG, "[onPlayFromMediaId] Duration esta vale $duration")
      } else {
        if (!filePath.isNullOrEmpty()) duration = MediaUtils.getMp3Duration(filePath);
         else duration = 0

        Log.i(TAG, "[onPlayFromMediaId] Duration esta no vale $duration")
      }
      return duration
    }

    if (mediaSessionContext == "MEDIA_AUTOPLAY") {
      Log.d(TAG, "Blocking autoplay triggered by Android Auto")
      // Optionally reset state or ignore
      return
    }

    // Handle play_all: and shuffle: action items from album/playlist drill-down
    if (mediaId != null && (mediaId.startsWith("play_all:") || mediaId.startsWith("shuffle:"))) {
      val shouldShuffle = mediaId.startsWith("shuffle:")
      val parts = mediaId.split(":")
      // Format: play_all:type:id or shuffle:type:id
      if (parts.size >= 3) {
        val actionMediaType = parts[1]
        val actionItemId = parts[2]
        Log.i(TAG, "[ACTION_PLAY] action=${if (shouldShuffle) "shuffle" else "play_all"} type=$actionMediaType id=$actionItemId")

        // Construct the original browsable mediaId to fetch children
        val browsableMediaId = "item_${actionMediaType}_${actionItemId}"
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val allItems = MediaItemTree.getRemoteChildren(browsableMediaId, context)
            // Filter out action items (play_all:/shuffle:), keep only real tracks
            val tracks = allItems.filter { item ->
              val mid = item.mediaId ?: ""
              !mid.startsWith("play_all:") && !mid.startsWith("shuffle:")
            }
            val playTracks = if (shouldShuffle) tracks.shuffled() else tracks
            Log.i(TAG, "[ACTION_PLAY] Fetched ${tracks.size} tracks, shuffle=$shouldShuffle")

            QueueManager.buildQueue(playTracks)
            withContext(Dispatchers.Main) {
              QueueManager.setQueue(mediaSession)
              playTracks.firstOrNull()?.let { first ->
                val fe = first.description.extras!!
                val trackIdFromId = fe.getString("id")
                val idAlbumTrack = fe.getString("idAlbumTrack")
                val uri = LocalStorageUtils.getTrackUri(context, trackIdFromId, idAlbumTrack)

                mediaPlayer.setCurrentTrack(uri)
                mediaPlayer.playCurrentTrack(context)
                updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
                val duration = getDurationStringLength(fe.getString("length"), uri.toString())

                mediaSession.setMetadata(
                  MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, fe.getString("title"))
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, fe.getString("artist"))
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, fe.getString("album"))
                    .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, fe.getString("image"))
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                    .build()
                )
                showNotification(PlaybackStateCompat.STATE_PLAYING)
                storeLocalData(fe, idAlbumTrack)
                Log.i(TAG, "[ACTION_PLAY] Started playback successfully")
              }
            }
          } catch (e: Exception) {
            Log.e(TAG, "[ACTION_PLAY] Error: ${e.message}", e)
          }
        }
        return
      }
    }

    // Extraer mediaType del mediaId si extras es nulo
    var mediaType: String? = extras?.getString("media_type")
    if (mediaType == null && mediaId != null) {
      // Espera formato: item_type_id
      val parts = mediaId.split("_")
      if (parts.size >= 3) {
        mediaType = parts[1]
      }
    }

    // autoplay artist: queue all tracks and play first
    if (mediaType == "artist" && mediaId != null) {
      CoroutineScope(Dispatchers.IO).launch {
        val tracks = MediaItemTree.getRemoteChildren(mediaId, context)
        QueueManager.buildQueue(tracks)
        withContext(Dispatchers.Main) {
          QueueManager.setQueue(mediaSession)
          tracks.firstOrNull()?.let { first ->
            val fe = first.description.extras!!
            val trackId = fe.getString("idAlbumTrack")
            val uri = LocalStorageUtils.getTrackUri(context, fe.getString("id"), trackId)
            mediaPlayer.setCurrentTrack(uri)
            mediaPlayer.playCurrentTrack(context)
            updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
            val duration = getDurationStringLength(fe.getString("length",), uri.toString())
            mediaSession.setMetadata(
              MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, fe.getString("title"))
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, fe.getString("artist"))
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, fe.getString("album"))
                .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, fe.getString("image"))
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                .build()
            )
            showNotification(PlaybackStateCompat.STATE_PLAYING)
            storeLocalData(fe, trackId)
          }
        }
      }
      return
    }

    // Track radio: play selected track + load related tracks
    if (mediaType == "track" && mediaId != null) {
      Log.i(TAG, "[TRACK_RADIO_START] Starting track radio for mediaId: $mediaId")
      val selectedItem = MediaItemTree.getItem(mediaId)
      if (selectedItem != null) {
        val fe = selectedItem.description.extras!!
        val trackIdForApi = fe.getString("id") ?: mediaId.split("_").lastOrNull() ?: ""
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val tracks = MediaItemTree.getTrackRadioQueue(selectedItem, trackIdForApi, context)
            Log.i(TAG, "[TRACK_RADIO_TRACKS] Got ${tracks.size} tracks for radio queue")
            QueueManager.buildQueue(tracks)
            withContext(Dispatchers.Main) {
              QueueManager.setQueue(mediaSession)
              tracks.firstOrNull()?.let { first ->
                val extras = first.description.extras!!
                val idAlbumTrack = extras.getString("idAlbumTrack")
                val uri = LocalStorageUtils.getTrackUri(context, extras.getString("id"), idAlbumTrack)
                Log.i(TAG, "[TRACK_RADIO_URI] Track URI resolved: $uri")

                mediaPlayer.setCurrentTrack(uri)
                mediaPlayer.playCurrentTrack(context)
                updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
                val duration = getDurationStringLength(extras.getString("length"), uri.toString())

                mediaSession.setMetadata(
                  MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras.getString("title"))
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras.getString("artist"))
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras.getString("album"))
                    .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, extras.getString("image"))
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                    .build()
                )
                showNotification(PlaybackStateCompat.STATE_PLAYING)
                storeLocalData(extras, idAlbumTrack)
                Log.i(TAG, "[TRACK_RADIO_SUCCESS] Track radio started successfully")
              }
            }
          } catch (e: Exception) {
            Log.e(TAG, "[TRACK_RADIO_ERROR] Exception: ${e.message}", e)
          }
        }
        return
      }
    }

    // radio_track from Recents: same as track radio - play selected track + related tracks
    if (mediaType == "radio_track" && mediaId != null) {
      Log.i(TAG, "[RADIO_TRACK_START] Starting radio_track for mediaId: $mediaId")
      val selectedItem = MediaItemTree.getItem(mediaId)
      if (selectedItem != null) {
        val fe = selectedItem.description.extras!!
        val trackIdForApi = fe.getString("id") ?: mediaId.split("_").lastOrNull() ?: ""
        Log.i(TAG, "[RADIO_TRACK_INFO] trackId=$trackIdForApi, idAlbumTrack=${fe.getString("idAlbumTrack")}")
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val tracks = MediaItemTree.getTrackRadioQueue(selectedItem, trackIdForApi, context)
            Log.i(TAG, "[RADIO_TRACK_QUEUE] Got ${tracks.size} tracks for radio queue")
            QueueManager.buildQueue(tracks)
            withContext(Dispatchers.Main) {
              QueueManager.setQueue(mediaSession)
              tracks.firstOrNull()?.let { first ->
                val trackExtras = first.description.extras!!
                val idAlbumTrack = trackExtras.getString("idAlbumTrack")
                val uri = LocalStorageUtils.getTrackUri(context, trackExtras.getString("id"), idAlbumTrack)
                Log.i(TAG, "[RADIO_TRACK_URI] Track URI resolved: $uri")

                mediaPlayer.setCurrentTrack(uri)
                mediaPlayer.playCurrentTrack(context)
                updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
                val duration = getDurationStringLength(trackExtras.getString("length"), uri.toString())

                mediaSession.setMetadata(
                  MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, trackExtras.getString("title"))
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, trackExtras.getString("artist"))
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, trackExtras.getString("album"))
                    .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, trackExtras.getString("image"))
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                    .build()
                )
                showNotification(PlaybackStateCompat.STATE_PLAYING)

                // Override parentData with TRACK_RADIO type + full trackData from extras
                val trackJson = trackExtras.getString("track") ?: "{}"
                val radioParentData = JSONObject().apply {
                  put("type", "TRACK_RADIO")
                  put("id", trackIdForApi)
                  put("trackData", JSONObject(trackJson))
                }.toString()
                val radioExtras = Bundle(trackExtras)
                radioExtras.putString("parentData", radioParentData)
                storeLocalData(radioExtras, idAlbumTrack)
                Log.i(TAG, "[RADIO_TRACK_SUCCESS] radio_track started successfully with TRACK_RADIO parentData")
              }
            }
          } catch (e: Exception) {
            Log.e(TAG, "[RADIO_TRACK_ERROR] Exception: ${e.message}", e)
          }
        }
        return
      } else {
        Log.w(TAG, "[RADIO_TRACK_NOT_FOUND] Item not found in treeNodes for $mediaId")
      }
    }

    // radio (tag_radio) from Recents: fetch tracks from stations endpoint
    if (mediaType == "radio" && mediaId != null) {
      Log.i(TAG, "[TAG_RADIO_START] Starting tag radio for mediaId: $mediaId")
      // mediaId format: item_radio_148 -> extract "148"
      val stationId = mediaId.removePrefix("item_radio_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }
      Log.i(TAG, "[TAG_RADIO_INFO] stationId=$stationId")

      val parentItem = MediaItemTree.getItem(mediaId)
      val itemName = parentItem?.description?.title?.toString() ?: ""
      val parentData = JSONObject().apply {
        put("type", "RADIO")
        put("id", stationId)
        put("name", itemName)
      }.toString()

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val tracks = MediaItemTree.getStationRadioQueue(stationId, parentData, context)
          Log.i(TAG, "[TAG_RADIO_QUEUE] Got ${tracks.size} tracks for station $stationId")
          if (tracks.isNotEmpty()) {
            QueueManager.buildQueue(tracks)
            withContext(Dispatchers.Main) {
              QueueManager.setQueue(mediaSession)
              val first = tracks.first()
              val trackExtras = first.description.extras!!
              val idAlbumTrack = trackExtras.getString("idAlbumTrack")
              val uri = LocalStorageUtils.getTrackUri(context, trackExtras.getString("id"), idAlbumTrack)
              Log.i(TAG, "[TAG_RADIO_URI] Track URI resolved: $uri")

              mediaPlayer.setCurrentTrack(uri)
              mediaPlayer.playCurrentTrack(context)
              updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
              val duration = getDurationStringLength(trackExtras.getString("length"), uri.toString())

              mediaSession.setMetadata(
                MediaMetadataCompat.Builder()
                  .putString(MediaMetadataCompat.METADATA_KEY_TITLE, trackExtras.getString("title"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, trackExtras.getString("artist"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, trackExtras.getString("album"))
                  .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, trackExtras.getString("image"))
                  .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                  .build()
              )
              showNotification(PlaybackStateCompat.STATE_PLAYING)
              storeLocalData(trackExtras, idAlbumTrack)
              Log.i(TAG, "[TAG_RADIO_SUCCESS] Tag radio started successfully")
            }
          } else {
            Log.w(TAG, "[TAG_RADIO_NO_TRACKS] No tracks returned for station $stationId")
          }
        } catch (e: Exception) {
          Log.e(TAG, "[TAG_RADIO_ERROR] Exception: ${e.message}", e)
        }
      }
      return
    }

    // artist_radio from Recents: fetch artist tracks (shuffled), same as JS app
    if (mediaType == "artist_radio" && mediaId != null) {
      Log.i(TAG, "[ARTIST_RADIO_START] Starting artist radio for mediaId: $mediaId")
      // mediaId format: item_artist_radio_6766 -> extract "6766"
      val artistId = mediaId.removePrefix("item_artist_radio_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }
      Log.i(TAG, "[ARTIST_RADIO_INFO] artistId=$artistId")

      val parentItem = MediaItemTree.getItem(mediaId)
      val itemName = parentItem?.description?.title?.toString() ?: ""
      val parentData = JSONObject().apply {
        put("type", "ARTIST_STATION")
        put("id", artistId)
        put("name", itemName)
      }.toString()

      CoroutineScope(Dispatchers.IO).launch {
        try {
          // Use getArtistTracks (same as JS app: /artists/{id}/tracks?order=popularity)
          val response = MediaItemTree.getArtistRadioQueue(artistId, parentData, context)
          Log.i(TAG, "[ARTIST_RADIO_QUEUE] Got ${response.size} tracks for artist $artistId")
          if (response.isNotEmpty()) {
            // Shuffle like JS app does (Fisher-Yates)
            val shuffled = response.toMutableList().apply { shuffle() }
            QueueManager.buildQueue(shuffled)
            withContext(Dispatchers.Main) {
              QueueManager.setQueue(mediaSession)
              val first = shuffled.first()
              val trackExtras = first.description.extras!!
              val idAlbumTrack = trackExtras.getString("idAlbumTrack")
              val uri = LocalStorageUtils.getTrackUri(context, trackExtras.getString("id"), idAlbumTrack)
              Log.i(TAG, "[ARTIST_RADIO_URI] Track URI resolved: $uri")

              mediaPlayer.setCurrentTrack(uri)
              mediaPlayer.playCurrentTrack(context)
              updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
              val duration = getDurationStringLength(trackExtras.getString("length"), uri.toString())

              mediaSession.setMetadata(
                MediaMetadataCompat.Builder()
                  .putString(MediaMetadataCompat.METADATA_KEY_TITLE, trackExtras.getString("title"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, trackExtras.getString("artist"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, trackExtras.getString("album"))
                  .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, trackExtras.getString("image"))
                  .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                  .build()
              )
              showNotification(PlaybackStateCompat.STATE_PLAYING)
              storeLocalData(trackExtras, idAlbumTrack)
              Log.i(TAG, "[ARTIST_RADIO_SUCCESS] Artist radio started successfully")
            }
          } else {
            Log.w(TAG, "[ARTIST_RADIO_NO_TRACKS] No tracks returned for artist $artistId")
          }
        } catch (e: Exception) {
          Log.e(TAG, "[ARTIST_RADIO_ERROR] Exception: ${e.message}", e)
        }
      }
      return
    }

    if (mediaType == "album" && mediaId != null) {
      // autoplay album: fetch tracks, queue, and play first
      Log.i(TAG, "[ALBUM_AUTOPLAY_START] Starting album autoplay for mediaId: $mediaId")
      CoroutineScope(Dispatchers.IO).launch {
        try {
          Log.d(TAG, "[ALBUM_AUTOPLAY_FETCH] Fetching tracks for album: $mediaId")
          val allItems = MediaItemTree.getRemoteChildren(mediaId, context)
          // Filter out action items (play_all:/shuffle:), keep only real tracks
          val tracks = allItems.filter { item ->
            val mid = item.mediaId ?: ""
            !mid.startsWith("play_all:") && !mid.startsWith("shuffle:")
          }
          Log.i(TAG, "[ALBUM_AUTOPLAY_TRACKS_FETCHED] Fetched ${tracks.size} tracks for album")

          QueueManager.buildQueue(tracks)
          withContext(Dispatchers.Main) {
            QueueManager.setQueue(mediaSession)
            tracks.firstOrNull()?.let { first ->
              Log.d(TAG, "[ALBUM_AUTOPLAY_FIRST_TRACK] Processing first track: ${first.description.mediaId}")

              val fe = first.description.extras!!
              val trackIdFromId = fe.getString("id")
              val idAlbumTrack = fe.getString("idAlbumTrack")

              Log.i(TAG, "[ALBUM_AUTOPLAY_TRACK_INFO] Track ID: $trackIdFromId, idAlbumTrack: $idAlbumTrack")

              // Check if idAlbumTrack is null or "null" string
              if (idAlbumTrack == null || idAlbumTrack == "null") {
                Log.w(TAG, "[ALBUM_AUTOPLAY_NULL_ALBUMTRACK] idAlbumTrack is null or 'null' string, this may cause issues")
              }

              Log.d(TAG, "[ALBUM_AUTOPLAY_GET_URI] Calling LocalStorageUtils.getTrackUri with trackId=$trackIdFromId, idAlbumTrack=$idAlbumTrack")
              val uri = LocalStorageUtils.getTrackUri(context, trackIdFromId, idAlbumTrack)
              Log.i(TAG, "[ALBUM_AUTOPLAY_URI_RESOLVED] Track URI resolved: $uri")

              mediaPlayer.setCurrentTrack(uri)
              mediaPlayer.playCurrentTrack(context)
              updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
              val duration = getDurationStringLength(fe.getString("length",), uri.toString())
              Log.d(TAG, "[ALBUM_AUTOPLAY_DURATION] Track duration: $duration ms")

              mediaSession.setMetadata(
                MediaMetadataCompat.Builder()
                  .putString(MediaMetadataCompat.METADATA_KEY_TITLE, fe.getString("title"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, fe.getString("artist"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, fe.getString("album"))
                  .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, fe.getString("image"))
                  .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                  .build()
              )
              showNotification(PlaybackStateCompat.STATE_PLAYING)
              storeLocalData(fe, idAlbumTrack)
              Log.i(TAG, "[ALBUM_AUTOPLAY_SUCCESS] Album autoplay started successfully")
            } ?: run {
              Log.w(TAG, "[ALBUM_AUTOPLAY_NO_TRACKS] No tracks found in album")
            }
          }
        } catch (e: Exception) {
          Log.e(TAG, "[ALBUM_AUTOPLAY_ERROR] Exception during album autoplay: ${e.message}", e)
          Log.e(TAG, "[ALBUM_AUTOPLAY_STACK_TRACE] ${e.stackTraceToString()}")
        }
      }
      return
    }

    // autoplay playlist: queue all tracks and play first
    if (mediaType == "playlist" && mediaId != null) {
      Log.i(TAG, "[PLAYLIST_AUTOPLAY_START] Starting playlist autoplay for mediaId: $mediaId")
      CoroutineScope(Dispatchers.IO).launch {
        try {
          Log.d(TAG, "[PLAYLIST_AUTOPLAY_FETCH] Fetching tracks for playlist: $mediaId")
          val allItems = MediaItemTree.getRemoteChildren(mediaId, context)
          // Filter out action items (play_all:/shuffle:), keep only real tracks
          val tracks = allItems.filter { item ->
            val mid = item.mediaId ?: ""
            !mid.startsWith("play_all:") && !mid.startsWith("shuffle:")
          }
          Log.i(TAG, "[PLAYLIST_AUTOPLAY_TRACKS_FETCHED] Fetched ${tracks.size} tracks for playlist")

          QueueManager.buildQueue(tracks)
          withContext(Dispatchers.Main) {
            QueueManager.setQueue(mediaSession)
            tracks.firstOrNull()?.let { first ->
              Log.d(TAG, "[PLAYLIST_AUTOPLAY_FIRST_TRACK] Processing first track: ${first.description.mediaId}")

              val fe = first.description.extras!!
              val trackIdFromId = fe.getString("id")
              val idAlbumTrack = fe.getString("idAlbumTrack")

              Log.i(TAG, "[PLAYLIST_AUTOPLAY_TRACK_INFO] Track ID: $trackIdFromId, idAlbumTrack: $idAlbumTrack")

              // Check if idAlbumTrack is null or "null" string
              if (idAlbumTrack == null || idAlbumTrack == "null") {
                Log.w(TAG, "[PLAYLIST_AUTOPLAY_NULL_ALBUMTRACK] idAlbumTrack is null or 'null' string, this may cause issues")
              }

              Log.d(TAG, "[PLAYLIST_AUTOPLAY_GET_URI] Calling LocalStorageUtils.getTrackUri with trackId=$trackIdFromId, idAlbumTrack=$idAlbumTrack")
              val uri = LocalStorageUtils.getTrackUri(context, trackIdFromId, idAlbumTrack)
              Log.i(TAG, "[PLAYLIST_AUTOPLAY_URI_RESOLVED] Track URI resolved: $uri")

              mediaPlayer.setCurrentTrack(uri)
              mediaPlayer.playCurrentTrack(context)
              updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
              val duration: Long = getDurationStringLength(fe.getString("length",), uri.toString())
              Log.d(TAG, "[PLAYLIST_AUTOPLAY_DURATION] Track duration: $duration ms")

              mediaSession.setMetadata(
                MediaMetadataCompat.Builder()
                  .putString(MediaMetadataCompat.METADATA_KEY_TITLE, fe.getString("title"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, fe.getString("artist"))
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, fe.getString("album"))
                  .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
                  .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, fe.getString("image"))
                  .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                  .build()
              )
              showNotification(PlaybackStateCompat.STATE_PLAYING)
              storeLocalData(fe, idAlbumTrack)
              Log.i(TAG, "[PLAYLIST_AUTOPLAY_SUCCESS] Playlist autoplay started successfully")
            } ?: run {
              Log.w(TAG, "[PLAYLIST_AUTOPLAY_NO_TRACKS] No tracks found in playlist")
            }
          }
        } catch (e: Exception) {
          Log.e(TAG, "[PLAYLIST_AUTOPLAY_ERROR] Exception during playlist autoplay: ${e.message}", e)
          Log.e(TAG, "[PLAYLIST_AUTOPLAY_STACK_TRACE] ${e.stackTraceToString()}")
        }
      }
      return
    }

    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[onPlayFromMediaId] Start $mediaId")
      val trackId = extras?.getString("idAlbumTrack")
      Log.i(TAG, "[onPlayFromMediaId] trackId $trackId")

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val trackUrl: Uri? = LocalStorageUtils.getTrackUri(context, extras?.getString("id"),
            trackId)
          withContext(Dispatchers.Main) {
            Log.i(TAG, "[onPlayFromMediaId] Current track $trackUrl")
            QueueManager.setQueue(mediaSession)
            mediaPlayer.setCurrentTrack(trackUrl)
            mediaPlayer.playCurrentTrack(context)

            updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
            var durationText = extras?.getString("length", "0");
           val durationMs = getDurationStringLength(durationText, trackUrl.toString())
            val metadata = MediaMetadataCompat.Builder()
              .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras?.getString("title"))
              .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras?.getString("artist"))
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras?.getString("album"))
              .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, extras?.getString("image"))
              .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
              .build()

            mediaSession.setMetadata(metadata)

            showNotification(PlaybackStateCompat.STATE_PLAYING)

            //storeLocalData(extras, trackId)
            extras?.let { storeLocalData(it, trackId) }
          }
        } catch (e: Exception) {
          Log.e("MediaSession", "Failed to load track URI", e)
        }
      }
    }
  }

  override fun onPlay() {
    Log.i(TAG, "[ON_PLAY] onPlay() called, isPreparing: ${mediaPlayer.isPreparing()}, isPlaying: ${mediaPlayer.isPlaying()}")
    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[ON_PLAY_EXECUTE] Executing play command")

      // If the player is already playing, just update state and return
      if (mediaPlayer.isPlaying()) {
        Log.i(TAG, "[ON_PLAY_ALREADY_PLAYING] Player is already playing, just updating state")
        updateState(PlaybackStateCompat.STATE_PLAYING)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        CordovaEventBridge.sendEvent(
          CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
          JSONObject().put("action", "play"))
        return
      }

      // Request audio focus before starting playback
      Log.i(TAG, "[ON_PLAY_REQUEST_FOCUS] Requesting audio focus")
      val hasFocus = mediaPlayer.requestAudioFocusForPlayback()
      Log.i(TAG, "[ON_PLAY_FOCUS_RESULT] Audio focus granted: $hasFocus")

      if (hasFocus) {
        mediaPlayer.play()
        updateState(PlaybackStateCompat.STATE_PLAYING)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        CordovaEventBridge.sendEvent(
          CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
          JSONObject().put("action", "play"))
        Log.i(TAG, "[ON_PLAY_COMPLETE] Play command completed, isPlaying: ${mediaPlayer.isPlaying()}")
      } else {
        Log.w(TAG, "[ON_PLAY_NO_FOCUS] Could not gain audio focus, playback not started")
        updateState(PlaybackStateCompat.STATE_PAUSED)
      }
    } else {
      Log.w(TAG, "[ON_PLAY_SKIP] Skipping play because isPreparing is true")
    }
  }

  override fun onStop() {
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.stop()
      updateState(PlaybackStateCompat.STATE_STOPPED, 0)
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      showNotification(PlaybackStateCompat.STATE_STOPPED)
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "stop"))
    }
  }

  override fun onPause() {
    Log.i(TAG, "[ON_PAUSE] onPause() called at position: ${mediaPlayer.currentPosition}, isPreparing: ${mediaPlayer.isPreparing()}, isPlaying: ${mediaPlayer.isPlaying()}")

    // Log stack trace to see where pause is being called from
    val stackTrace = Thread.currentThread().stackTrace
    val caller = if (stackTrace.size > 3) stackTrace[3] else null
    Log.i(TAG, "[ON_PAUSE_CALLER] Called from: ${caller?.className}.${caller?.methodName}:${caller?.lineNumber}")

    // Check if we should ignore pause commands during audio focus stabilization period
    if (mediaPlayer.shouldIgnorePauseCommands()) {
      Log.w(TAG, "[ON_PAUSE_IGNORED] Ignoring pause command during audio focus stabilization period")
      return
    }

    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[ON_PAUSE_EXECUTE] Executing pause command")
      mediaPlayer.pause()
      updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
      showNotification(PlaybackStateCompat.STATE_PAUSED)
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "pause"))
      Log.i(TAG, "[ON_PAUSE_COMPLETE] Pause command completed")
    } else {
      Log.w(TAG, "[ON_PAUSE_SKIP] Skipping pause because isPreparing is true")
    }
  }

  override fun onSkipToNext() {
    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[ON_SKIP_TO_NEXT] Skip to next triggered from Android Auto")
      // Reset flags and enable auto-play for the next track
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true
      Log.i(TAG, "[ON_SKIP_TO_NEXT] Set shouldAutoPlayOnPrepare = true for auto-play")

      val nextItem = QueueManager.getNextQueueItem(mediaSession)
      if (nextItem != null) {
        Log.i(TAG, "[ON_SKIP_TO_NEXT] Got next item: ${nextItem.description.mediaId}")
        onPlayFromMediaId(
          mediaId = nextItem.description.mediaId,
          extras = nextItem.description.extras
        )
      } else {
        Log.w(TAG, "[ON_SKIP_TO_NEXT] No next item available (queue might be empty)")
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToNext"))
    }
  }

  override fun onSkipToPrevious() {
    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[ON_SKIP_TO_PREVIOUS] Skip to previous triggered from Android Auto")
      // Reset flags and enable auto-play for the previous track
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true
      Log.i(TAG, "[ON_SKIP_TO_PREVIOUS] Set shouldAutoPlayOnPrepare = true for auto-play")

      val previousItem = QueueManager.getPreviousQueueItem(mediaSession)
      if (previousItem != null) {
        Log.i(TAG, "[ON_SKIP_TO_PREVIOUS] Got previous item: ${previousItem.description.mediaId}")
        onPlayFromMediaId(
          mediaId = previousItem.description.mediaId,
          extras = previousItem.description.extras
        )
      } else {
        Log.w(TAG, "[ON_SKIP_TO_PREVIOUS] No previous item available (queue might be empty)")
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToPrevious"))
    }
  }

  override fun onSeekTo(pos: Long) {
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.seekTo(pos)

      updateState(
        if (mediaPlayer.isPlaying()) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
        pos
      )

      if (mediaPlayer.isPlaying()) {
        handler.removeCallbacks(updatePlaybackPositionRunnable)
        handler.post(updatePlaybackPositionRunnable)
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "seekTo").put("value", pos))
    }
  }

  override fun onSkipToQueueItem(id: Long) {
    if(!mediaPlayer.isPreparing()) {
      Log.i(TAG, "[ON_SKIP_TO_QUEUE_ITEM] Skip to queue item triggered from Android Auto")
      // Reset flags and enable auto-play for the selected track
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true
      Log.i(TAG, "[ON_SKIP_TO_QUEUE_ITEM] Set shouldAutoPlayOnPrepare = true for auto-play")

      val nextItem = QueueManager.getItem(mediaSession, id)
      if(nextItem != null) {
        onPlayFromMediaId(
          mediaId = nextItem.description.mediaId,
          extras = nextItem.description.extras
        )
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToQueueItem"))
    }
  }

  private fun storeLocalData(extras: Bundle, trackId: String?) {
    if(mediaSession.controller.queue !== null) {
      val stringQueue = mediaSession.controller.queue.map { it ->
        "{ \"data\":" + it.description.extras?.getString("track") + " }"
      }
      val playlistData = extras.getString("parentData")
      LocalStorageUtils.storeInFile(context, QUEUE_ITEMS_KEY, stringQueue.toString())
      LocalStorageUtils.storeInFile(context, PLAYLIST_DATA, playlistData)
      LocalStorageUtils.storeDataInPrefs(context, CURRENT_TRACK_KEY, trackId.toString())

      CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE)
    }
  }

  private fun updateState(
    state: Int,
    position: Long = mediaPlayer.currentPosition
  ) {
    //Log.i(TAG, "[MediaSessionCallback] Update state $state")
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
      .setState(state, position, 1f)
      .build()
    mediaSession.setPlaybackState(pb)
  }

  private fun handlePrepare() {
    Log.i(TAG, "[HANDLE_PREPARE_START] handling prepare callback")
    Log.i(TAG, "[HANDLE_PREPARE_FROM_APP] currentTrackFromApp flag: ${mediaPlayer.currentTrackFromApp}")
    Log.i(TAG, "[HANDLE_PREPARE_AUTO_PLAY] shouldAutoPlayOnPrepare flag: ${mediaPlayer.shouldAutoPlayOnPrepare}")
    Log.i(TAG, "[HANDLE_PREPARE_IS_PLAYING] mediaPlayer.isPlaying: ${mediaPlayer.isPlaying()}")
    Log.i(TAG, "[HANDLE_PREPARE_POSITION] currentPosition: ${mediaPlayer.currentPosition}")

    // Sync the queue index with the current track
    val currentMediaId = mediaSession.controller.metadata?.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID)
    QueueManager.syncCurrentIndex(mediaSession, currentMediaId)

    // Check if we should auto-play (explicitly requested from app)
    if(mediaPlayer.shouldAutoPlayOnPrepare) {
      Log.i(TAG, "[HANDLE_PREPARE_AUTO_PLAY_TRUE] Auto-play requested, starting playback")
      mediaPlayer.shouldAutoPlayOnPrepare = false

      // Request audio focus before starting playback
      Log.i(TAG, "[HANDLE_PREPARE_REQUEST_FOCUS_AUTO] Requesting audio focus for auto-play")
      val hasFocus = mediaPlayer.requestAudioFocusForPlayback()
      Log.i(TAG, "[HANDLE_PREPARE_FOCUS_RESULT_AUTO] Audio focus granted: $hasFocus")

      if (hasFocus) {
        Log.i(TAG, "[HANDLE_PREPARE_START_PLAYBACK_AUTO] Starting playback via mediaPlayer.start()")
        mediaPlayer.start()
        Log.i(TAG, "[HANDLE_PREPARE_AFTER_START_AUTO] mediaPlayer.isPlaying after start: ${mediaPlayer.isPlaying()}")
        updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        showNotification(PlaybackStateCompat.STATE_PLAYING)
        Log.i(TAG, "[HANDLE_PREPARE_COMPLETE_AUTO] Auto-play started successfully")
      } else {
        Log.w(TAG, "[HANDLE_PREPARE_NO_FOCUS_AUTO] Could not gain audio focus for auto-play, setting to PAUSED")
        updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
        showNotification(PlaybackStateCompat.STATE_PAUSED)
      }
    } else if(mediaPlayer.currentTrackFromApp) {
      // Track from app but no auto-play - just prepare and leave in STOPPED state
      Log.i(TAG, "[HANDLE_PREPARE_FROM_APP_NO_AUTO] Track from app, setting to STOPPED state (no auto-play)")
      mediaPlayer.currentTrackFromApp = false
      updateState(PlaybackStateCompat.STATE_STOPPED, mediaPlayer.currentPosition)
    } else {
      // Normal playback from Android Auto (e.g., user clicked a song)
      // Request audio focus again right before starting playback
      // This helps prevent race conditions with audio focus loss
      Log.i(TAG, "[HANDLE_PREPARE_REQUEST_FOCUS] Requesting audio focus before starting playback")
      val hasFocus = mediaPlayer.requestAudioFocusForPlayback()
      Log.i(TAG, "[HANDLE_PREPARE_FOCUS_RESULT] Audio focus granted: $hasFocus")

      if (hasFocus) {
        Log.i(TAG, "[HANDLE_PREPARE_START_PLAYBACK] Starting playback via mediaPlayer.start()")
        mediaPlayer.start()
        Log.i(TAG, "[HANDLE_PREPARE_AFTER_START] mediaPlayer.isPlaying after start: ${mediaPlayer.isPlaying()}")
        updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        showNotification(PlaybackStateCompat.STATE_PLAYING)
        Log.i(TAG, "[HANDLE_PREPARE_COMPLETE] Playback started successfully")
      } else {
        Log.w(TAG, "[HANDLE_PREPARE_NO_FOCUS] Could not gain audio focus, playback not started")
        updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
        showNotification(PlaybackStateCompat.STATE_PAUSED)
      }
    }
  }

  private fun handleError(what: Int, extra: Int) {
    var userFacingMessage = "An unknown error occurred during playback."
    val logMessage = StringBuilder("MediaPlayer Error: ")
    var shouldRecreatePlayer = false

    when (what) {
      MediaPlayer.MEDIA_ERROR_UNKNOWN -> {
        logMessage.append("UNKNOWN_ERROR")
        when (extra) {
          MediaPlayer.MEDIA_ERROR_IO -> {
            userFacingMessage = "Could not load the track. Please check your internet connection or try again."
            logMessage.append(" (IO Error - Network/File issue)")
          }
          MediaPlayer.MEDIA_ERROR_MALFORMED -> {
            userFacingMessage = "The track is corrupted or not in a recognizable format."
            logMessage.append(" (Malformed Media)")
          }
          MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> {
            userFacingMessage = "This media format is not supported."
            logMessage.append(" (Unsupported Media)")
          }
          MediaPlayer.MEDIA_ERROR_TIMED_OUT -> {
            userFacingMessage = "Playback timed out. Check your connection."
            logMessage.append(" (Timed Out)")
          }
          else -> {
            userFacingMessage = "An unexpected error occurred."
            logMessage.append(" (Extra: $extra)")
          }
        }
      }
      MediaPlayer.MEDIA_ERROR_SERVER_DIED -> {
        userFacingMessage = "The media playback system encountered a critical error. Please restart the app."
        logMessage.append("SERVER_DIED - Critical error, player needs full re-initialization.")
        shouldRecreatePlayer = true
      }
      else -> {
        userFacingMessage = "Playback failed. Please try a different track."
        logMessage.append(" (What: $what, Extra: $extra)")
      }
    }

    Log.e(TAG, logMessage.toString())

    // 1. Stop periodic position updates immediately
    handler.removeCallbacks(updatePlaybackPositionRunnable)

    // 2. Manage MediaPlayer state
    try {
      mediaPlayer.stop() // Stop any current playback
      if (shouldRecreatePlayer) {
        mediaPlayer.release()
      } else {
        mediaPlayer.reset() // Reset to Idle for reuse
      }
    } catch (e: IllegalStateException) {
      Log.e("MyPlaybackService", "Error during player cleanup after error: ${e.message}")
      // Fallback to full release if reset fails
      mediaPlayer.release()
    }

    // 3. Update MediaSessionCompat state to ERROR
    // Crucial to inform external controllers about the problem
    val errorMessageState = PlaybackStateCompat.Builder()
      .setState(PlaybackStateCompat.STATE_ERROR, 0, 1.0f)
      .setErrorMessage(PlaybackStateCompat.ERROR_CODE_UNKNOWN_ERROR, userFacingMessage) // Provide user-friendly message
      .setActions(0) // No actions available when in error state
      .build()
    mediaSession.setPlaybackState(errorMessageState)


    // 4. (Optional) Inform the user in the main UI
    // You'd typically use a broadcast or EventBus to send this message to your Activity/Fragment
    // Example (requires LocalBroadcastManager setup or similar):
    // val errorIntent = Intent("my_app.playback_error")
    // errorIntent.putExtra("message", userFacingMessage)
    // LocalBroadcastManager.getInstance(applicationContext).sendBroadcast(errorIntent)

    // 5. (Optional) Implement recovery logic
    // For example, if you have a playlist and the current track failed,
    // you might try to skip to the next one automatically.
    // For this, you would need to manage your playlist index.
    // skipToNextTrackIfAvailable() // Your custom function
  }

  private fun handleAudioFocusChange(focusChange: Int) {
    Log.i(TAG, "[HANDLE_AUDIO_FOCUS] Audio focus change received: $focusChange")

    when (focusChange) {
      android.media.AudioManager.AUDIOFOCUS_GAIN -> {
        Log.i(TAG, "[HANDLE_AUDIO_FOCUS_GAIN] Audio focus regained - updating state to PLAYING")
        // When we regain audio focus, immediately update the state to PLAYING
        // This prevents Android Auto from auto-pausing after we regain focus
        if (mediaPlayer.isPlaying()) {
          updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
          // Ensure the periodic position updates are running
          handler.removeCallbacks(updatePlaybackPositionRunnable)
          handler.post(updatePlaybackPositionRunnable)
          mediaSession.isActive = true
          Log.i(TAG, "[HANDLE_AUDIO_FOCUS_GAIN] State updated to PLAYING successfully")
        }
      }
      android.media.AudioManager.AUDIOFOCUS_LOSS -> {
        Log.w(TAG, "[HANDLE_AUDIO_FOCUS_LOSS] Audio focus lost permanently - pausing playback")
        // Another app has taken audio focus permanently (e.g., user started playing in Spotify)
        // We must pause immediately
        if (mediaPlayer.isPlaying()) {
          mediaPlayer.pause()
          updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
          handler.removeCallbacks(updatePlaybackPositionRunnable)
          Log.i(TAG, "[HANDLE_AUDIO_FOCUS_LOSS] Playback paused due to permanent audio focus loss")
        }
      }
      android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
        Log.w(TAG, "[HANDLE_AUDIO_FOCUS_LOSS_TRANSIENT] Transient audio focus loss - pausing playback")
        // Temporary interruption (e.g., notification, phone call)
        // Pause but expect to resume when focus is regained
        if (mediaPlayer.isPlaying()) {
          mediaPlayer.pause()
          updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
          handler.removeCallbacks(updatePlaybackPositionRunnable)
          Log.i(TAG, "[HANDLE_AUDIO_FOCUS_LOSS_TRANSIENT] Playback paused due to transient audio focus loss")
        }
      }
      android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
        Log.w(TAG, "[HANDLE_AUDIO_FOCUS_DUCK] Audio focus loss, can duck - pausing playback")
        // Can lower volume (duck) but in Android Auto context, it's better to pause
        // to avoid multiple audio sources playing simultaneously
        if (mediaPlayer.isPlaying()) {
          mediaPlayer.pause()
          updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
          handler.removeCallbacks(updatePlaybackPositionRunnable)
          Log.i(TAG, "[HANDLE_AUDIO_FOCUS_DUCK] Playback paused to avoid simultaneous audio")
        }
      }
    }
  }

  private fun handlePlaybackCompletion() {
    Log.i(TAG, "[PLAYBACK_COMPLETION] Media playback completed. Stopping and resetting player.")
    mediaPlayer.stop()
    mediaPlayer.reset()
    updateState(PlaybackStateCompat.STATE_STOPPED, 0)
    handler.removeCallbacks(updatePlaybackPositionRunnable)
    onSkipToNext()
  }

  private val updatePlaybackPositionRunnable: Runnable = object : Runnable {
    override fun run() {
      try {
        if (mediaPlayer.isPlaying()) {
        //  Log.i(TAG, "[MediaSessionCallback] Update Playback position, player is playing")
          val currentPosition = mediaPlayer.currentPosition
          val currentState =
            PlaybackStateCompat.STATE_PLAYING

          updateState(currentState, currentPosition)
        }
        handler.postDelayed(this, PLAYBACK_POSITION_UPDATE_INTERVAL)
      } catch (e: Exception) {
        // Prevent app to break when disconnected.
      }

    }
  }

  private fun showNotification(state: Int) {
    val controller = mediaSession.controller
    val mediaMetadata = controller.metadata
    val description = mediaMetadata?.description

    // Check for notification permission on Android 13+
    val hasNotificationPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
              android.content.pm.PackageManager.PERMISSION_GRANTED
    } else {
      true
    }

    if (!hasNotificationPermission) {
      Log.w(TAG, "Notification permission not granted, not showing notification")
      return
    }

    // Create notification channel for API 26+
    val channelName = "Media Playback"
    val channelDescription = "Media playback controls"
    val importance = NotificationManager.IMPORTANCE_LOW
    val channel = NotificationChannel(CHANNEL_ID, channelName, importance)
    channel.description = channelDescription
    val notificationManager = context.getSystemService(NotificationManager::class.java)
    notificationManager.createNotificationChannel(channel)

    val mainActivityIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
    val contentIntent = PendingIntent.getActivity(
      context, 0, mainActivityIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val builder = NotificationCompat.Builder(context, CHANNEL_ID).apply {
      setContentTitle(description?.title)
      setContentText(description?.subtitle)
      setSubText(description?.description)
      setContentIntent(contentIntent)
      setSmallIcon(context.applicationInfo.icon)
      setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      if (state == PlaybackStateCompat.STATE_PLAYING) {
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_previous, "Previous",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_pause, "Pause",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_PAUSE)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_next, "Next",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
        ))
      } else {
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_previous, "Previous",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_play, "Play",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_PLAY)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_next, "Next",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
        ))
      }
      setStyle(androidx.media.app.NotificationCompat.MediaStyle()
        .setMediaSession(mediaSession.sessionToken)
        .setShowActionsInCompactView(0, 1, 2))
      setWhen(System.currentTimeMillis() - (mediaPlayer.currentPosition))
      setUsesChronometer(state == PlaybackStateCompat.STATE_PLAYING)
      setOngoing(state == PlaybackStateCompat.STATE_PLAYING)
    }

    val imageUri = description?.iconUri
    val imageUrl = imageUri?.toString()
    if (imageUrl != null) {
      CoroutineScope(Dispatchers.IO).launch {
        try {
          Log.i(TAG, "[NOTIFICATION_IMAGE_START] Loading notification image: $imageUrl")

          // Check if this is a local FileProvider URI
          val isFileProvider = imageUrl.startsWith("content://") &&
                               (imageUrl.contains(".fileprovider") ||
                                imageUrl.contains(".auto.file.provider") ||
                                imageUrl.contains(".cdv.core.file.provider"))

          val bitmap = if (isFileProvider) {
            Log.i(TAG, "[NOTIFICATION_IMAGE_LOCAL] Detected local FileProvider image: $imageUrl")

            // Grant permission to system UI for notification
            try {
              context.grantUriPermission(
                "com.android.systemui",
                imageUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
              )
              Log.i(TAG, "[NOTIFICATION_IMAGE_PERMISSION] Granted READ permission to com.android.systemui")
            } catch (e: Exception) {
              Log.w(TAG, "[NOTIFICATION_IMAGE_PERMISSION_WARN] Could not grant permission to systemui: ${e.message}")
            }

            // Load bitmap from ContentResolver
            Log.d(TAG, "[NOTIFICATION_IMAGE_LOAD_LOCAL] Loading bitmap from ContentResolver")
            context.contentResolver.openInputStream(imageUri)?.use { inputStream ->
              BitmapFactory.decodeStream(inputStream)
            } ?: run {
              Log.w(TAG, "[NOTIFICATION_IMAGE_LOAD_FAILED] Could not open InputStream for local image")
              null
            }
          } else {
            // Remote image - load from URL
            Log.i(TAG, "[NOTIFICATION_IMAGE_REMOTE] Loading remote image from URL")
            val url = URL(imageUrl)
            BitmapFactory.decodeStream(url.openConnection().getInputStream())
          }

          if (bitmap != null) {
            Log.i(TAG, "[NOTIFICATION_IMAGE_SUCCESS] Bitmap loaded successfully, size: ${bitmap.width}x${bitmap.height}")
            withContext(Dispatchers.Main) {
              builder.setLargeIcon(bitmap)
              safelyShowNotification(NOTIFICATION_ID, builder.build())
            }
          } else {
            Log.w(TAG, "[NOTIFICATION_IMAGE_NULL] Bitmap is null, showing notification without image")
          }
        } catch (e: Exception) {
          Log.e(TAG, "[NOTIFICATION_IMAGE_ERROR] Error loading notification image: ${e.message}", e)
          Log.e(TAG, "[NOTIFICATION_IMAGE_STACK_TRACE] ${e.stackTraceToString()}")
        }
      }
    }
    val notification = builder.build()
    safelyShowNotification(NOTIFICATION_ID, notification)

    // Only call startForeground if permission is granted
    if (state == PlaybackStateCompat.STATE_PLAYING && context is Service) {
      try {
        context.startForeground(NOTIFICATION_ID, notification)
      } catch (e: SecurityException) {
        Log.w(TAG, "No notification permission for startForeground", e)
      }
    } else if (context is Service) {
      context.stopForeground(false)
    }
  }


  // Add this helper method to check permissions before showing notifications
  private fun safelyShowNotification(notificationId: Int, notification: android.app.Notification) {
    // Check for notification permission on Android 13+
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      if (context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
        android.content.pm.PackageManager.PERMISSION_GRANTED) {
        NotificationManagerCompat.from(context).notify(notificationId, notification)
      } else {
        Log.w(TAG, "Notification permission not granted")
      }
    } else {
      // For Android 12 and below, no runtime permission needed
      NotificationManagerCompat.from(context).notify(notificationId, notification)
    }
  }

}
