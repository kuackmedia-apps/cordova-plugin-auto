package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AutoNavigationExplorer (
  val text: String,
  val icon: String,
  val items: List<MediaItem>
)
