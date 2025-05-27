package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class RecentListened (
  val id: String,
  val data: MediaItem,
  val type: String,
)

