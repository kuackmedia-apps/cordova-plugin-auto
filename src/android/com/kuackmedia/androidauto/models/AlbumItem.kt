package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AlbumItem(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  val upc: String?,
  val title: String,
  val subTitle: String?,
  val tracksQty: Int?,
  val releaseDate: String,
  val active: Boolean,
  val images: List<CoverImage>,
  val artists: List<Artist>,
  val score: Double?,
  val imageColorInfo: ImageColorInfo? = null,
) : MediaItem()
