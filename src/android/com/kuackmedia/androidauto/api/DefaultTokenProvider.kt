package com.kuackmedia.androidauto.api

import android.content.SharedPreferences

interface TokenProvider {
  fun getToken(): String?
  fun saveToken(token: String)
  suspend fun refreshToken(): String?
}

class DefaultTokenProvider(
  private val prefs: SharedPreferences,
  private val api: MusicApi
) : TokenProvider {
  companion object {
    private const val KEY_TOKEN = "KEY_TOKEN"
  }

  override fun getToken(): String? =
    prefs.getString(KEY_TOKEN, null)

  override fun saveToken(token: String) {
    prefs.edit().putString(KEY_TOKEN, token).apply()
  }

  override suspend fun refreshToken(): String? {
    // Call the ping endpoint to get a fresh token
    val response = api.ping()
    val newToken = response.token
    if (!newToken.isNullOrBlank()) {
      saveToken(newToken)
      return newToken
    }
    return null
  }
}
