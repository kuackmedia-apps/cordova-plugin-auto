package com.kuackmedia.androidauto

import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.util.Log
import com.kuackmedia.androidauto.media.MusicLibraryService
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class AndroidAutoPlugin : CordovaPlugin() {
  private var carModeReceiver: BroadcastReceiver? = null

  @Throws(JSONException::class)
  override fun execute(
    action: String?,
    args: JSONArray?,
    callbackContext: CallbackContext
  ): Boolean {
    if ("startService" == action) {
      val ctx = cordova.context
      val intent = Intent(ctx, MusicLibraryService::class.java)
      ctx.startService(intent)
      Log.d(TAG, "Android Auto startService:")
      callbackContext.success("Servicio Android Auto iniciado")
      return true
    } else if ("isConnected" == action) {
      val isConnected = this.isConnectedToAndroidAuto
      Log.d(TAG, "Android Auto connected: $isConnected")
      callbackContext.success(if (isConnected) 1 else 0)
      return true
    } else if ("registerAutoConnectListener" == action) {
      connectionEventCallback = callbackContext
      registerAutoConnectListener()
      val pluginResult = PluginResult(PluginResult.Status.NO_RESULT)
      pluginResult.keepCallback = true
      callbackContext.sendPluginResult(pluginResult)
      return true
    } else if ("unregisterAutoConnectListener" == action) {
      unregisterAutoConnectListener()
      callbackContext.success("Listener eliminado")
      return true
    } else if ("getHardcodedPlaylists" == action) {
      getHardcodedPlaylists(callbackContext)
      return true
    } else if ("getHardcodedPlaylistTracks" == action) {
      val playlistId = args?.getString(0) ?: ""
      getHardcodedPlaylistTracks(playlistId, callbackContext)
      return true
    } else if ("playHardcodedTrack" == action) {
      val trackUrl = args?.getString(0) ?: ""
      val metadata = args?.getJSONObject(1) ?: JSONObject()
      playHardcodedTrack(trackUrl, metadata, callbackContext)
      return true
    }
    return false
  }

  private val isConnectedToAndroidAuto: Boolean
    get() {
      val uiModeManager =
        cordova.activity.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager?
      if (uiModeManager != null) {
        return (uiModeManager.getCurrentModeType() == Configuration.UI_MODE_TYPE_CAR)
      }
      return false
    }


  private fun registerAutoConnectListener() {
    if (carModeReceiver != null) {
      unregisterAutoConnectListener()
    }

    carModeReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent) {
        val action = intent.action
        if (action != null && action == UiModeManager.ACTION_ENTER_CAR_MODE ||
          action == UiModeManager.ACTION_EXIT_CAR_MODE ||
          action == Intent.ACTION_CONFIGURATION_CHANGED
        ) {
          val isConnected: Boolean = isConnectedToAndroidAuto
          sendConnectionEvent(isConnected)
        }
      }
    }

    val filter = IntentFilter()
    filter.addAction(UiModeManager.ACTION_ENTER_CAR_MODE)
    filter.addAction(UiModeManager.ACTION_EXIT_CAR_MODE)
    filter.addAction(Intent.ACTION_CONFIGURATION_CHANGED)
    cordova.activity.registerReceiver(carModeReceiver, filter)
  }

  private fun unregisterAutoConnectListener() {
    if (carModeReceiver != null) {
      try {
        cordova.activity.unregisterReceiver(carModeReceiver)
        carModeReceiver = null
      } catch (e: Exception) {
        // Receptor ya desregistrado
      }
    }
  }

  private fun sendConnectionEvent(isConnected: Boolean) {
    try {
      val eventData = JSONObject()
      eventData.put("connected", isConnected)

      val result = PluginResult(PluginResult.Status.OK, eventData)
      result.keepCallback = true

      // El segundo parámetro debería ser una CallbackContext guardada durante el registro
      // Aquí se necesitaría guardar callbackContext durante registerAutoConnectListener
      if (connectionEventCallback != null) {
        connectionEventCallback!!.sendPluginResult(result)
      }
    } catch (e: JSONException) {
      // Error al crear JSON
    }
  }

  private var connectionEventCallback: CallbackContext? = null

  override fun onDestroy() {
    unregisterAutoConnectListener()
    super.onDestroy()
  }

  /**
   * Returns a list of hardcoded playlists
   */
  private fun getHardcodedPlaylists(callbackContext: CallbackContext) {
    try {
      val playlists = JSONArray()
      
      // Create three hardcoded playlists matching the ones in MediaItemTree
      val playlist1 = JSONObject()
      playlist1.put("id", "hardcoded_playlist_1")
      playlist1.put("name", "Featured Tracks")
      playlist1.put("description", "Our featured music collection")
      playlists.put(playlist1)
      
      val playlist2 = JSONObject()
      playlist2.put("id", "hardcoded_playlist_2")
      playlist2.put("name", "Sample Music")
      playlist2.put("description", "Sample tracks for demonstration")
      playlists.put(playlist2)
      
      val playlist3 = JSONObject()
      playlist3.put("id", "hardcoded_playlist_3")
      playlist3.put("name", "Favorites")
      playlist3.put("description", "Your favorite tracks")
      playlists.put(playlist3)
      
      callbackContext.success(playlists)
    } catch (e: Exception) {
      Log.e(TAG, "Error getting hardcoded playlists", e)
      callbackContext.error("Failed to get hardcoded playlists: ${e.message}")
    }
  }
  
  /**
   * Returns tracks for a hardcoded playlist
   */
  private fun getHardcodedPlaylistTracks(playlistId: String, callbackContext: CallbackContext) {
    try {
      val tracks = JSONArray()
      
      // Create a sample track that matches the one in MediaItemTree
      val track = JSONObject()
      track.put("id", "${playlistId}_track_1")
      track.put("title", "SoundHelix Song 1")
      track.put("artist", "T. Schürger")
      track.put("album", "SoundHelix Samples")
      track.put("url", "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")
      track.put("duration", 372000) // Approximate duration in ms
      tracks.put(track)
      
      callbackContext.success(tracks)
    } catch (e: Exception) {
      Log.e(TAG, "Error getting tracks for playlist $playlistId", e)
      callbackContext.error("Failed to get tracks: ${e.message}")
    }
  }
  
  /**
   * Plays a hardcoded track directly
   */
  private fun playHardcodedTrack(trackUrl: String, metadata: JSONObject, callbackContext: CallbackContext) {
    try {
      val ctx = cordova.context
      val intent = Intent(ctx, MusicLibraryService::class.java)
      intent.action = "PLAY_HARDCODED_TRACK"
      intent.putExtra("track_url", trackUrl)
      intent.putExtra("track_title", metadata.optString("title", "Unknown Title"))
      intent.putExtra("track_artist", metadata.optString("artist", "Unknown Artist"))
      intent.putExtra("track_album", metadata.optString("album", "Unknown Album"))
      ctx.startService(intent)
      
      callbackContext.success("Playing hardcoded track")
    } catch (e: Exception) {
      Log.e(TAG, "Error playing hardcoded track", e)
      callbackContext.error("Failed to play track: ${e.message}")
    }
  }
  
  companion object {
    private const val TAG = "AndroidAutoPlugin"
  }
}
