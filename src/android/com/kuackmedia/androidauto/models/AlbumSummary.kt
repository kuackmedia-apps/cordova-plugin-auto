package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AlbumSummary(
  val id: Long,
  val upc: String? = null,
  val score: Double? = null,
  val title: String? = null,
  val active: Boolean? = null,
  val images: List<CoverImage>? = null,
  val artists: List<Artist>? = null,
  val itemType: String? = null,
  val subTitle: String? = null,
  val tracksQty: Int? = null,
  val releaseDate: String? = null,
  val imageColorInfo: ImageColorInfo? = null
)
