package com.kuackmedia.androidauto

import android.util.Log
import org.apache.cordova.CallbackContext
import org.apache.cordova.PluginResult
import org.json.JSONObject

object CordovaEventBridge {
    val TAG = "CordovaEventBridge"
    var eventCallbackContext = mutableMapOf<String, CallbackContext>()

    fun sendEvent(event: String, payload: JSONObject = JSONObject()) {
        eventCallbackContext[event]?.let {
            payload.put("event", event)
            Log.i(TAG, "Sending event $event")
            Log.i(TAG, "Sending event payload $payload")
            val result = PluginResult(PluginResult.Status.OK, payload)
            result.keepCallback = true
            it.sendPluginResult(result)
        }
    }
}
