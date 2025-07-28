package com.kuackmedia.androidauto.media

import android.content.Intent
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import androidx.media.MediaBrowserServiceCompat
import androidx.media.session.MediaButtonReceiver
import androidx.media.utils.MediaConstants
import com.kuackmedia.androidauto.CordovaEventBridge
import com.kuackmedia.androidauto.CordovaEvents
import com.kuackmedia.androidauto.api.ServiceFactory
import com.kuackmedia.androidauto.tree.MediaItemTree
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject


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
    const val QUEUE_ITEMS_KEY = "QUEUE_ITEMS_KEY"
    const val PLAYLIST_DATA = "playlist_data"
  }

  private var currentTrackName: String? = null
  private val serviceJob = SupervisorJob()
  private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

  private lateinit var mediaSession: MediaSessionCompat
  private lateinit var playerAdapter: IPlayerAdapter

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    MediaButtonReceiver.handleIntent(mediaSession, intent)
    return super.onStartCommand(intent, flags, startId)
  }

  override fun onCreate() {
    super.onCreate()

    CordovaEventBridge.sendEvent(
      CordovaEvents.ON_CONNECTION_CHANGE,
      JSONObject().put("connected", true))

    initApiData()

    val musicApi = ServiceFactory.create(applicationContext)

    playerAdapter = MediaPlayerAdapter()

    MediaItemTree.initialize(applicationContext, musicApi)

    if (!::mediaSession.isInitialized) {
      mediaSession = MediaSessionCompat(this, TAG)
      mediaSession.setFlags(
        MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
          MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
      )
      mediaSession.setCallback(MediaSessionCallback(playerAdapter, mediaSession, applicationContext))
    }

    setSessionToken(mediaSession.sessionToken)

    MediaControlBridge.mediaSession = mediaSession
    MediaControlBridge.mediaPlayer = playerAdapter

    mediaSession.controller.transportControls.prepare()
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

    MediaControlBridge.setConnected(true)

    return BrowserRoot(ROOT_ID, extras)
  }

  override fun onUnbind(intent: Intent?): Boolean {
    MediaControlBridge.setConnected(false)
    return super.onUnbind(intent)
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
          QueueManager.buildQueue( remoteChildren)
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
    playerAdapter.stop()
    playerAdapter.reset()
    mediaSession.release()
    playerAdapter.release()

    CordovaEventBridge.sendEvent(
      CordovaEvents.ON_CONNECTION_CHANGE,
      JSONObject().put("connected", false))

    super.onDestroy()
  }

  override fun onSearch(
    query: String, extras: Bundle?,
    result: Result<MutableList<MediaBrowserCompat.MediaItem?>?>
  ) {
    Log.d("Search", "Received search query: $query")
    result.detach() // Notify the system you'll send the result asynchronously
    serviceScope.launch {
      try {
        val items = MediaItemTree.search(query)
        result.sendResult(items.toMutableList<MediaBrowserCompat.MediaItem?>())
      } catch (e: Exception) {
        Log.e("MusicLibraryService", "Search failed", e)
        result.sendResult(mutableListOf())
      }
    }
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
    Log.i(TAG, "CURRENT_TRACK_KEY: ${this.currentTrackName}")
  }
}
