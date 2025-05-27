package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class ImageColorInfo(
  val value: List<Int>,
  val rgb: String,
  val rgba: String,
  val hex: String,
  val hexa: String,
  val isDark: Boolean,
  val isLight: Boolean
)
