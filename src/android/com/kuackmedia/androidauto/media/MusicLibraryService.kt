package com.kuackmedia.androidauto.media

import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import androidx.media.MediaBrowserServiceCompat
import androidx.media.utils.MediaConstants
import com.kuackmedia.androidauto.api.ServiceFactory
import com.kuackmedia.androidauto.tree.MediaItemTree
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch


class MusicLibraryService : MediaBrowserServiceCompat() {

  companion object {
    const val TAG = "MusicLibraryService"
    const val AT_EXP_TIME_KEY = "AT_EXP_TIME_KEY"
    const val REFRESH_TOKEN_KEY = "REFRESH_TOKEN_KEY"
    const val ACCESS_TOKEN_KEY = "AT_TOKEN_KEY"
    const val APP_KUACK_CODE = "APP_KUACK_CODE"
    const val API_URL = "API_URL"
    const val DEVICE_ID = "DEVICE_ID"
    const val ROOT_ID = "[rootID]"
    const val CURRENT_TRACK_KEY = "current_track"
  }

  private var currentTrackName: String? = null
  private val serviceJob = SupervisorJob()
  private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

  private lateinit var mediaSession: MediaSessionCompat
  private lateinit var playerAdapter: IPlayerAdapter
  private lateinit var currentQueue: List<MediaSessionCompat.QueueItem>
  private var currentTrack: MediaBrowserCompat.MediaItem? = null

  override fun onCreate() {
    super.onCreate()

    initApiData()

    val musicApi = ServiceFactory.create(applicationContext)

    playerAdapter = MediaPlayerAdapter(this)
    MediaItemTree.initialize(applicationContext, musicApi)

    this.currentQueue = CurrentMedia.getCurrentQueue(applicationContext)!!
    this.currentTrack =
      CurrentMedia.getCurrentTrackFromQueue(
        this.currentTrackName!!,
        this.currentQueue
      )

    mediaSession = MediaSessionCompat(this, TAG).apply {
      setCallback(MediaSessionCallback(playerAdapter, this))
    }

    if(this.currentQueue.isNotEmpty()) {
      Log.i(TAG, "Setting queue")
      mediaSession.setQueue(this.currentQueue)

      if(this.currentTrack !== null) {
        Log.i(TAG, "Setting current track")
        playerAdapter.setCurrentTrack(this.currentTrack);

        mediaSession.setMetadata(
          MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID,
              this.currentTrack!!.description.mediaId
            )
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE,
              this.currentTrack!!.description.title.toString())
            .putString(
              MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI,
              this.currentTrack!!.description.iconUri.toString())
            .build()
        )
      }
    }

    mediaSession.setActive(true)

    setSessionToken(mediaSession.sessionToken)
  }

  override fun onGetRoot(
    clientPackageName: String,
    clientUid: Int,
    rootHints: Bundle?
  ): BrowserRoot? {
    val extras = Bundle()
    extras.putInt(
      MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
      MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM)
    extras.putInt(
      MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_PLAYABLE,
      MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM)
    extras.putBoolean(MediaConstants.BROWSER_SERVICE_EXTRAS_KEY_SEARCH_SUPPORTED, true)
    return BrowserRoot(ROOT_ID, extras)
  }

  override fun onLoadChildren(
    parentId: String,
    result: Result<List<MediaBrowserCompat.MediaItem?>?>
  ) {
    result.detach()
    Log.d(TAG, "[OnLoadChildren] parentId: $parentId")
    val localChildren = MediaItemTree.getChildren(parentId)

    if(localChildren.isNotEmpty()) {
      result.sendResult(localChildren)
    } else {
      serviceScope.launch {
        try {
          val remoteChildren = MediaItemTree.getRemoteChildren(parentId)
          result.sendResult(remoteChildren)
        } catch (e: Exception) {
          Log.e("MusicService", "Error loading children", e)
          result.sendResult(mutableListOf())
        }
      }
    }
  }

  override fun onDestroy() {
    Log.i(TAG, "onDestroy called")
    mediaSession.release()
    super.onDestroy()
  }

  override fun onSearch(
    query: String, extras: Bundle?,
    result: Result<MutableList<MediaBrowserCompat.MediaItem?>?>
  ) {
    Log.d("Search", "Received search query: $query")
    result.sendResult(MediaItemTree.search(query))
  }

  private fun initApiData() {
    val prefs = applicationContext.getSharedPreferences("NativeStorage", MODE_PRIVATE)
    val refreshToken = prefs.getString(REFRESH_TOKEN_KEY, null)
    val accessToken = prefs.getString(ACCESS_TOKEN_KEY, null)
    val accessTokenExpiration = prefs.getString(AT_EXP_TIME_KEY, null)
    val appKuackCode = prefs.getString(APP_KUACK_CODE, null)
    val deviceId = prefs.getString(DEVICE_ID, null)
    val baseUrl = prefs.getString(API_URL, null)

    this.currentTrackName = prefs.getString(CURRENT_TRACK_KEY, null).toString().replace("\"", "")

    Log.i(TAG, "REFRESH_TOKEN_KEY: $refreshToken")
    Log.i(TAG, "ACCESS_TOKEN_KEY: $accessToken")
    Log.i(TAG, "AT_EXP_TIME_KEY: $accessTokenExpiration")
    Log.i(TAG, "APP_KUACK_CODE: $appKuackCode")
    Log.i(TAG, "API_URL: $baseUrl")
    Log.i(TAG, "DeviceID: $deviceId")
  }
}
