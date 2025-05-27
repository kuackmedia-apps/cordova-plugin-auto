package com.kuackmedia.androidauto.api

import kotlinx.coroutines.runBlocking
import okhttp3.Authenticator
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route

class TokenAuthenticator(
  private val tokenProvider: TokenProvider
) : Authenticator {
  override fun authenticate(route: Route?, response: Response): Request? {
    // avoid infinite loops
    if (responseCount(response) >= 2) return null

    // refresh token
    val newToken = runBlocking { tokenProvider.refreshToken() } ?: return null

    // retry original request with new token
    return response.request
      .newBuilder()
      .header("Authorization", "Bearer $newToken")
      .build()
  }

  private fun responseCount(response: Response): Int {
    var res: Response? = response
    var count = 0
    while (res != null) {
      count++
      res = res.priorResponse
    }
    return count
  }
}

