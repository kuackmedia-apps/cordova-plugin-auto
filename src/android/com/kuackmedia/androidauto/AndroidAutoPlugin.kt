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
    when (action) {
      "registerEvents" -> {
        CordovaEventBridge.eventCallbackContext = callbackContext

        val result = PluginResult(PluginResult.Status.NO_RESULT)
        result.keepCallback = true
        callbackContext.sendPluginResult(result)
        return true
      }

      "startService" -> {
        val ctx = cordova.context
        val intent = Intent(ctx, MusicLibraryService::class.java)
        ctx.startService(intent)
        Log.d(TAG, "Android Auto startService:")
        callbackContext.success("Servicio Android Auto iniciado")
        return true
      }

      "isConnectedToAndroidAuto" -> {
        val isConnected = this.isConnectedToAndroidAuto
        Log.d(TAG, "Android Auto connected: $isConnected")
        callbackContext.success(if (isConnected) 1 else 0)
        return true
      }

      "registerAutoConnectListener" -> {
        connectionEventCallback = callbackContext
        registerAutoConnectListener()
        val pluginResult = PluginResult(PluginResult.Status.NO_RESULT)
        pluginResult.keepCallback = true
        callbackContext.sendPluginResult(pluginResult)
        return true
      }

      "unregisterAutoConnectListener" -> {
        unregisterAutoConnectListener()
        callbackContext.success("Listener eliminado")
        return true
      }
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

  companion object {
    private const val TAG = "AndroidAutoPlugin"
  }
}
