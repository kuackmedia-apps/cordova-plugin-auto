package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class EmptyModel(
  override val id: String = "0",
  override val itemStyle: String = "grid",
  override val itemType: String = "empty",
  override val score: Double? = null
) : MediaItem()
