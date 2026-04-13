package com.kuackmedia.androidauto.api

import android.content.SharedPreferences
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import androidx.core.content.edit
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class TokenInterceptor(
    private val prefProvider: () -> SharedPreferences,
    private val baseUrl: String,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        var request = chain.request()
        val prefs = prefProvider();

        // Attach current token
        var accessToken = prefs.getString("AT_TOKEN_KEY", null);
        var refreshToken = prefs.getString("REFRESH_TOKEN_KEY", null);
        var appKuackCode = prefs.getString("APP_KUACK_CODE", null);
        var expirationAt = prefs.getString("AT_EXP_TIME_KEY", null);

        expirationAt = expirationAt?.replace("\"", "");
        //@todo check if expirationAt is valid
        accessToken = accessToken?.replace("\"", "");
        refreshToken = refreshToken?.replace("\"", "");
        appKuackCode = appKuackCode?.replace("\"", "");

        if (!accessToken.isNullOrEmpty()) {
            request = request.newBuilder()
                .addHeader("Authorization", "Bearer $accessToken")
                .addHeader("X-KUACK-APP", appKuackCode ?: "")
                .addHeader("content-type", "application/json")
                .build()
        }

        val response = chain.proceed(request)

        // If unauthorized, try to refresh token
        if (response.code == 401) {
            response.close() // close previous response to free resources

            val newToken = refreshAuthToken(refreshToken.toString(), appKuackCode.toString()) // Call /auth/ping

            return if (newToken != null) {
                val newRequest = request.newBuilder()
                    .removeHeader("Authorization")
                    .addHeader("Authorization", "Bearer $newToken")
                    .build()

                chain.proceed(newRequest)
            } else {
                response
            }
        }

        return response
    }

    private fun refreshAuthToken(refreshToken: String, appKuackCode: String): String? {
        val client = OkHttpClient()
        val prefs = prefProvider();

        val body = JSONObject()
        body.put("grantType", "refresh_token")
        body.put("token", refreshToken)

        val mediaType = "application/json".toMediaType()
        val requestBody = body.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url("${baseUrl}auth/token")
            .addHeader("Content-Type", "application/json")
            .addHeader("X-KUACK-APP", appKuackCode)
            .post(requestBody)
            .build()

        return try {
            client.newCall(request).execute().use { pingResponse ->
                val responseBody = pingResponse.body?.string()
                if (!responseBody.isNullOrEmpty()) {
                    val json = JSONObject(responseBody)
                    val newToken = json.getString("accessToken")
                    val refreshToken = json.getString("refreshToken")

                    prefs.edit {
                        putString("AT_TOKEN_KEY", "\"$newToken\"")
                        putString("REFRESH_TOKEN_KEY", "\"$refreshToken\"")
                    }
                    return newToken
                }
                null
            }
        } catch (e: IOException) {
            null
        }
    }
}
