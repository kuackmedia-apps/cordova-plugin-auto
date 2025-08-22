package com.kuackmedia.androidauto.utils

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

object TextsManager {
  private const val TAG = "TextManager"

  // holds the parsed JSON key→value map
  private lateinit var texts: Map<String, String>

  // must be called once (e.g. on Application start)
  fun init(context: Context) {
    val jsonFile = File(context.filesDir, "AUTO_TEXTS")
    texts = if (jsonFile.exists()) {
      try {
        val jsonString = jsonFile.readText()
        val jsonObject = JSONObject(jsonString)
        // build a Map<String,String> from all keys
        jsonObject.keys().asSequence().associateWith { key ->
          jsonObject.optString(key)
        }
        //log all json texts

      } catch (e: Exception) {
        Log.e(TAG, "Error parsing AUTO_TEXTS.json", e)
        emptyMap()
      }
    } else {
      Log.e(TAG, "AUTO_TEXTS.json not found")
      emptyMap()
    }
  }

  // returns the localized text or "" if not found
  fun getText(key: String): String {
    //log all texts
    Log.d(TAG, "Available texts: $texts")
    if (!::texts.isInitialized) {
      Log.e(TAG, "TextsManager not initialized. Call init() first.")
      return ""
    }
    // Log the key being accessed
    Log.d(TAG, "Accessing text for key: $key");
    //log all texts
    if (texts.isEmpty()) {
      Log.w(TAG, "No texts available. Check if init() was called successfully.")
      return ""
    }
    return texts[key] ?: ""
  }
}
