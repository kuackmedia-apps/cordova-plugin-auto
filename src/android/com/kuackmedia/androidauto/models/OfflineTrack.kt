package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class OfflineTrack(
  val trackData: Track,
  @Json(name = "ALBUM_ITEMS_OFFLINE") val albumItemsOffline: List<Int>? = null,
  @Json(name = "PLAYLISTS_ITEMS_OFFLINE") val playlistsItemsOffline: List<Int>? = null
)
