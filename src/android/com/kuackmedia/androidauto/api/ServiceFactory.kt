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
  // Construir la API es caro: dos Moshi con KotlinJsonAdapterFactory (kotlin-reflect
  // genera los adapters en runtime — segundos en frío en gama baja, y es la firma del
  // ANR de 2.004 usuarios en producción) + OkHttp + Retrofit. Se paga UNA vez por
  // proceso; antes se reconstruía TODO en cada llamada — incluida la del camino de
  // reproducción (LocalStorageUtils.getTrackUri) — re-pagando la reflexión, duplicando
  // connection pools y reasignando un lateinit sin sincronización.
  @Volatile
  private var api: MusicApi? = null

  fun create(context: Context): MusicApi {
    val existing = api
    if (existing != null) return existing
    synchronized(this) {
      val recheck = api
      if (recheck != null) return recheck

      // applicationContext: la instancia sobrevive al servicio y no debe retener
      // un Context de componente. SharedPreferences resuelve al mismo archivo.
      val appContext = context.applicationContext
      val prefs = { appContext.getSharedPreferences("NativeStorage", MODE_PRIVATE) }
      //val baseUrl = prefs().getString("API_URL", "https://api.prod.kuackmedia.com/api/")!!
      val baseUrl = "https://api.prod.kuackmedia.com/api/"

      val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.NONE
      }

      val interceptor = TokenInterceptor(prefProvider = prefs, baseUrl = baseUrl)
      val okHttpClient = OkHttpClient.Builder()
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

      val built = retrofit.create(MusicApi::class.java)
      api = built
      return built
    }
  }
}
