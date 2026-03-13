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
    private val pendingEvents = mutableMapOf<String, JSONObject>()

    fun sendEvent(event: CordovaEvents, payload: JSONObject = JSONObject()) {
        payload.put("event", event.value)
        val callback = eventCallbackContext[event.value]
        if (callback != null) {
            Log.i(TAG, "Sending event ${event.value}")
            Log.i(TAG, "Sending event payload $payload")
            val result = PluginResult(PluginResult.Status.OK, payload)
            result.keepCallback = true
            callback.sendPluginResult(result)
        } else {
            // Queue the event for delivery when the callback is registered
            Log.w(TAG, "No callback registered for ${event.value}, queuing event")
            pendingEvents[event.value] = payload
        }
    }

    /**
     * Called when a new callback is registered. Delivers any pending events.
     */
    fun deliverPendingEvents(eventName: String) {
        pendingEvents.remove(eventName)?.let { payload ->
            eventCallbackContext[eventName]?.let { callback ->
                Log.i(TAG, "Delivering pending event $eventName")
                val result = PluginResult(PluginResult.Status.OK, payload)
                result.keepCallback = true
                callback.sendPluginResult(result)
            }
        }
    }
}
