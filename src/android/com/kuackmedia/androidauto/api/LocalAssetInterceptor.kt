package com.kuackmedia.androidauto.api

import android.content.Context
import okhttp3.Interceptor
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.MediaType.Companion.toMediaType
import java.io.IOException

class LocalAssetInterceptor(
  private val context: Context,
  private val assetsFolder: String = "api_cache"
) : Interceptor {

  override fun intercept(chain: Interceptor.Chain): Response {
    val request = chain.request()

    // only for GETs
    if (request.method == "GET") {
      // e.g. GET https://api.yoursite.com/music/data  →  music_data.json
      val apiPath = request.url.encodedPath
        .trimStart('/')                      // "music/data"
      val fileName = apiPath
        .replace('/', '_') + ".json"         // "music_data.json"
      val assetPath = "$assetsFolder/$fileName"

      try {
        // try loading from assets/api_cache/<fileName>
        context.assets.open(assetPath).use { input ->
          val json = input.bufferedReader().readText()
          return Response.Builder()
            .code(200)
            .message("OK")
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .body(
              json.toResponseBody("application/json".toMediaType())
            )
            .addHeader("Content-Type", "application/json")
            .build()
        }
      } catch (e: IOException) {
        // asset not found → fall through to network
      }
    }

    // no local asset → real network call
    return chain.proceed(request)
  }
}
