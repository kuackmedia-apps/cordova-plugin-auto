package com.kuackmedia.androidauto

import android.util.Log
import org.apache.cordova.CallbackContext
import org.apache.cordova.PluginResult
import org.json.JSONObject

enum class CordovaEvents(val value: String) {
    ON_CONNECTION_CHANGE("onConnectionChange"),
    ON_MEDIA_UPDATE("onMediaUpdate"),
    ON_PLAYBACK_STATE_CHANGED("onPlaybackStateChange")
}

object CordovaEventBridge {
    val TAG = "CordovaEventBridge"
    var eventCallbackContext = mutableMapOf<String, CallbackContext>()

    fun sendEvent(event: CordovaEvents, payload: JSONObject = JSONObject()) {
        eventCallbackContext[event.value]?.let {
            payload.put("event", event.value)
            Log.i(TAG, "Sending event ${event.value}")
            Log.i(TAG, "Sending event payload $payload")
            val result = PluginResult(PluginResult.Status.OK, payload)
            result.keepCallback = true
            it.sendPluginResult(result)
        }
    }
}
