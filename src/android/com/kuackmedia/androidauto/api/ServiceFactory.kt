package com.kuackmedia.androidauto.api

import android.content.Context
import android.content.Context.MODE_PRIVATE
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.tree.MediaItemJsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import android.util.Log

object ServiceFactory {
  private var BASE_URL = "https://api.prod.kuackmedia.com/api/"
  private lateinit var okHttpClient: OkHttpClient


  fun create(context: Context): MusicApi {
    val prefs = context.getSharedPreferences("NativeStorage", MODE_PRIVATE)
   // BASE_URL = prefs.getString("API_URL", "")!!
    okHttpClient = OkHttpClient.Builder()
      .addInterceptor(TokenInterceptor { prefs})
      .build()

    val mediaItemAdapter = MediaItemJsonAdapter(
      Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()
    )
    val moshi = Moshi.Builder()
      .add(MediaItem::class.java, mediaItemAdapter)
      .add(KotlinJsonAdapterFactory())
      .build()

    val retrofit: Retrofit = Retrofit.Builder()
      .baseUrl(BASE_URL)
      .addConverterFactory(MoshiConverterFactory.create(moshi))
      .client(okHttpClient)
      .build()

    return retrofit.create(MusicApi::class.java)
  }
}
