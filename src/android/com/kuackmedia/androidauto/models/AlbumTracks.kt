package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AlbumTracks(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "list",
  override val score: Double? = null,
  val upc: String,
  val title: String,
  @Json(name = "subTitle") val subTitle: String?,
  val releaseType: String?,
  val lenght: String,
  val tracksQty: Int?,
  val releaseDate: String?,
  val active: Boolean?,
  val images: List<CoverImage>,
  val artists: List<Artist>?,
  val tracks: TracksContainer,
  val imageColorInfo: Any?
) : MediaItem()
