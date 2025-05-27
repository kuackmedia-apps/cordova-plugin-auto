package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class NavigationData(
  val icon: String,
  val text: String,
  val fileName: String,
)
