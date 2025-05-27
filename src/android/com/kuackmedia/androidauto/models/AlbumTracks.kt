package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AlbumTracks(
  val id: Long,
  val upc: String,
  val title: String,
  @Json(name = "subTitle") val subTitle: String?,
  val releaseType: String,
  val lenght: String,
  val tracksQty: Int,
  val releaseDate: String,
  val active: Boolean,
  val images: List<CoverImage>,
  val artists: List<Artist>,
  val tracks: TracksContainer,
  override val itemType: String,
  val imageColorInfo: Any?              // null in your payload
) : MediaItem()
