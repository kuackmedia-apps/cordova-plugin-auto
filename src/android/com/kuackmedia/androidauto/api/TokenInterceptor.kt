package com.kuackmedia.androidauto.api

import android.content.SharedPreferences
import android.util.Log
import okhttp3.Interceptor
import okhttp3.Response

class TokenInterceptor(private val prefProvider: () -> SharedPreferences) : Interceptor {
  override fun intercept(chain: Interceptor.Chain): Response {
    val prefs = prefProvider();
    var accessToken = prefs.getString("AT_TOKEN_KEY", null);
    var appKuackCode = prefs.getString("APP_KUACK_CODE", null);
    var expirationAt = prefs.getString("AT_EXP_TIME_KEY", null);
    expirationAt = expirationAt?.replace("\"", "");
  //@todo check if expirationAt is valid
    accessToken = accessToken?.replace("\"", "");
    appKuackCode = appKuackCode?.replace("\"", "");
    val request = chain.request().newBuilder()
        .addHeader("Authorization", "Bearer $accessToken")
        .addHeader("X-KUACK-APP", appKuackCode ?: "")
        .addHeader("content-type", "application/json")
        .build()

    Log.i("TokenInterceptor", request.headers.toString())
    Log.i("TokenInterceptor", accessToken ?: "No access token found")
    Log.i("TokenInterceptor", appKuackCode ?: "No App-Kuack-Code found")
    return chain.proceed(request)
  }
}
