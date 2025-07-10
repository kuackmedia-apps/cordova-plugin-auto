package com.kuackmedia.androidauto

import android.support.v4.media.session.PlaybackStateCompat
import com.kuackmedia.androidauto.media.MediaControlBridge
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONException

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
        return true
      }

      "play" -> {
        MediaControlBridge.play()
        callbackContext.success("Playing")
        return true
      }

      "pause" -> {
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

    }
    return false
  }
}
