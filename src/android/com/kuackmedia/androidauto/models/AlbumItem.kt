package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AlbumItem(
  val id: Int,
  val upc: String,
  val title: String,
  val subTitle: String?,
  val tracksQty: Int,
  val releaseDate: String,
  val active: Boolean,
  val images: List<CoverImage>,
  val artists: List<Artist>,
  val score: Double?,
  val imageColorInfo: ImageColorInfo?,
  override val itemType: String,
) : MediaItem()
