package com.kuackmedia.androidauto.api

import android.content.Context
import android.content.Context.MODE_PRIVATE
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.tree.MediaItemJsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

object ServiceFactory {
  private lateinit var okHttpClient: OkHttpClient

  fun create(context: Context): MusicApi {
    val prefs = { context.getSharedPreferences("NativeStorage", MODE_PRIVATE) }
    //val baseUrl = prefs().getString("API_URL", "https://api.prod.kuackmedia.com/api/")!!
    val baseUrl = "https://api.prod.kuackmedia.com/api/"

    val loggingInterceptor = HttpLoggingInterceptor().apply {
      level = HttpLoggingInterceptor.Level.NONE
    }

    val interceptor = TokenInterceptor(prefProvider = prefs, baseUrl = baseUrl)
    okHttpClient = OkHttpClient.Builder()
      .addInterceptor(loggingInterceptor)
      .addInterceptor(interceptor)
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
      .baseUrl(baseUrl)
      .addConverterFactory(MoshiConverterFactory.create(moshi))
      .client(okHttpClient)
      .build()

    return retrofit.create(MusicApi::class.java)
  }
}
