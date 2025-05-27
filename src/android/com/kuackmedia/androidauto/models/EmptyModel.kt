package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class EmptyModel(
  val id: String?,
  override val itemType: String = "empty"
) : MediaItem()
