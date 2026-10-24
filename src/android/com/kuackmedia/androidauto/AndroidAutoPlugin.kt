package com.kuackmedia.androidauto

import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import com.kuackmedia.androidauto.media.MediaControlBridge
import com.kuackmedia.androidauto.media.MusicLibraryService
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class AndroidAutoPlugin : CordovaPlugin() {
  @Throws(JSONException::class)
  override fun execute(
    action: String?,
    args: JSONArray?,
    callbackContext: CallbackContext
  ): Boolean {
    when (action) {
      "registerEvents" -> {
        val action = args!!.optString(0)
        CordovaEventBridge.eventCallbackContext[action] = callbackContext

        val result = PluginResult(PluginResult.Status.NO_RESULT)
        result.keepCallback = true
        callbackContext.sendPluginResult(result)

        // Deliver any events that were sent before this callback was registered
        CordovaEventBridge.deliverPendingEvents(action)
        return true
      }

      "play" -> {
        Log.i("AndroidAutoPlugin", "[JS_CMD] play")
        MediaControlBridge.play()
        callbackContext.success("Playing")
        return true
      }

      "pause" -> {
        Log.i("AndroidAutoPlugin", "[JS_CMD] pause")
        MediaControlBridge.pause()
        callbackContext.success("pause")
        return true
      }

      "getCurrentPlaybackState" -> {
        val state = MediaControlBridge.mediaSession?.controller?.playbackState?.state
        val label = when (state) {
          PlaybackStateCompat.STATE_PLAYING -> "PLAYING"
          PlaybackStateCompat.STATE_PAUSED -> "PAUSED"
          PlaybackStateCompat.STATE_STOPPED -> "STOPPED"
          PlaybackStateCompat.STATE_BUFFERING -> "BUFFERING"
          PlaybackStateCompat.STATE_NONE -> "NONE"
          else -> "unknown"
        }
        callbackContext.success(label)
        return true
      }

      "isConnected" -> {
        callbackContext.success(if (MediaControlBridge.androidAutoConnected) 1 else 0)
        return true
      }

      "getPosition" -> {
        callbackContext.success(MediaControlBridge.mediaPlayer?.currentPosition?.toInt() ?: 0)
        return true
      }

      "playCurrentTrack" -> {
        // Opcional: [{ startPositionMs }], la posición del teléfono en el traspaso teléfono → auto (getCapabilities la
        // declara como startPosition). El wrapper de myplugin.js manda [] y queda en 0.
        val startPositionMs = args?.optJSONObject(0)?.optLong("startPositionMs", 0L) ?: 0L
        Log.i("AndroidAutoPlugin", "[JS_CMD] playCurrentTrack startPositionMs=$startPositionMs")
        MediaControlBridge.playCurrentTrack(if (startPositionMs > 0) startPositionMs else 0L)
        callbackContext.success("Playing current track")
        return true
      }

      "getCapabilities" -> {
        // Lo que este plugin le garantiza al JS, que llega por OTA también a binarios con plugins anteriores (ahí la
        // acción no existe y Cordova responde INVALID_ACTION). loadGeneration: cada pedido de tema lleva generación
        // (beginTrackLoad), así que un playCurrentTrack del JS no se cruza con el prepare de la conexión (el traspaso
        // teléfono → auto de AutoSession lo exige). disconnectPosition: el aviso de desconexión trae positionMs.
        // startPosition: playCurrentTrack acepta [{ startPositionMs }] y la aplica sólo a ese pedido.
        callbackContext.success(
          JSONObject()
            .put("api", 1)
            .put("loadGeneration", true)
            .put("disconnectPosition", true)
            .put("startPosition", true)
        )
        return true
      }

      "updateNavigation" -> {
        try {
          MusicLibraryService.refreshNavigation()
          callbackContext.success("Navigation updated successfully")
        } catch (e: Exception) {
          Log.e("AndroidAutoPlugin", "[updateNavigation] Error: ${e.message}", e)
          callbackContext.error("Error updating navigation: ${e.message}")
        }
        return true
      }

    }
    return false
  }
}
