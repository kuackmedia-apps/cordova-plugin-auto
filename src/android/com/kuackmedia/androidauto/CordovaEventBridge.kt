package com.kuackmedia.androidauto

import org.apache.cordova.CallbackContext
import org.apache.cordova.PluginResult
import org.json.JSONObject

object CordovaEventBridge {
    var eventCallbackContext: CallbackContext? = null

    fun sendEvent(event: String, payload: JSONObject = JSONObject()) {
        eventCallbackContext?.let {
            payload.put("event", event)
            val result = PluginResult(PluginResult.Status.OK, payload)
            result.keepCallback = true
            it.sendPluginResult(result)
        }
    }
}
