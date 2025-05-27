package com.kuackmedia.androidauto.api

import android.content.Context
import android.content.SharedPreferences
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

const val URL = "http://192.168.1.7:3344/api/"

object ServiceFactory {
  fun create(context: Context): MusicApi {
    context.getSharedPreferences("auth", Context.MODE_PRIVATE)

    val moshi = Moshi.Builder()
      .add(KotlinJsonAdapterFactory()) // This is crucial for Kotlin classes
      .build()

    return Retrofit.Builder()
      .baseUrl(URL)
      .addConverterFactory(MoshiConverterFactory.create(moshi))
      .build()
      .create(MusicApi::class.java)

//    val tokenProvider = DefaultTokenProvider(
//      prefs,
//      simpleRetrofit.create(MusicApi::class.java)
//    )

    // 2) OkHttp client with:
    //    a) local-assets fallback
    //    b) bearer-token interceptor
    //    c) 401→refresh authenticator
//    val client = OkHttpClient.Builder()
//      //.addInterceptor(LocalAssetInterceptor(context))
//      .addInterceptor { chain ->
//        val req = chain.request().newBuilder().apply {
//          tokenProvider.getToken()?.let {
//            header("Authorization", "Bearer $it")
//          }
//        }.build()
//        chain.proceed(req)
//      }
//      .authenticator(TokenAuthenticator(tokenProvider))
//      .build()

    // 3) Retrofit that uses this client
//    return Retrofit.Builder()
//      .baseUrl(URL)
//      .client(client)
//      .addConverterFactory(MoshiConverterFactory.create())
//      .build()
//      .create(MusicApi::class.java)
  }
}
