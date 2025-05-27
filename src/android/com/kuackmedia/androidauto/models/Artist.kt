package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Artist(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  val name: String,
  val images: List<CoverImage>?,
  val active: Boolean?,
  val role: String?,
  val score: Double?,
  val imageColorInfo: Any?
) : MediaItem()
