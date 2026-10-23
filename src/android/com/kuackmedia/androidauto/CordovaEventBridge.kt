package com.kuackmedia.androidauto

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
            val result = PluginResult(PluginResult.Status.OK, payload)
            result.keepCallback = true
            callback.sendPluginResult(result)
        } else if (event != CordovaEvents.ON_PLAYBACK_STATE_CHANGED) {
            // ON_PLAYBACK_STATE_CHANGED no se encola: avisa un cambio, no es un estado. Guardado sin hora, llegaba al
            // registrarse el JS aunque fuera de minutos antes y dejaba mal el botón del app. El estado vigente lo lee
            // el JS de la sesión al registrarse (isConnected → syncCurrentTrackFromAuto → getCurrentPlaybackState).
            // Queue the event for delivery when the callback is registered
            pendingEvents[event.value] = payload
        }
    }

    /**
     * Called when a new callback is registered. Delivers any pending events.
     */
    fun deliverPendingEvents(eventName: String) {
        pendingEvents.remove(eventName)?.let { payload ->
            eventCallbackContext[eventName]?.let { callback ->
                val result = PluginResult(PluginResult.Status.OK, payload)
                result.keepCallback = true
                callback.sendPluginResult(result)
            }
        }
    }
}
