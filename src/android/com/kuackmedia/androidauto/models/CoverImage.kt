package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class CoverImage(
  val type: String? = null,
  val url: String? = null,
  val size: Int? = null,
  val imageType: String? = null,
  val list: List<String>? = null
)
