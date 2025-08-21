package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Artist(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  override val score: Double? = null,
  val name: String,
  val images: List<CoverImage>?,
  val active: Boolean?,
  val role: String?,
  val imageColorInfo: Any?
) : MediaItem()
