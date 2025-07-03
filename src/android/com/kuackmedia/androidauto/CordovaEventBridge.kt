package com.kuackmedia.androidauto

import android.util.Log
import org.apache.cordova.CallbackContext
import org.apache.cordova.PluginResult
import org.json.JSONObject

object CordovaEventBridge {
    val TAG = "CordovaEventBridge"
    var eventCallbackContext: CallbackContext? = null

    fun sendEvent(event: String, payload: JSONObject = JSONObject()) {
        eventCallbackContext?.let {
            Log.i(TAG, "Sending event $event")
            payload.put("event", event)
            val result = PluginResult(PluginResult.Status.OK, payload)
            result.keepCallback = true
            it.sendPluginResult(result)
        }
    }
}
