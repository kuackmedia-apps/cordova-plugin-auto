package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PlaylistTracks(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  override val score: Double? = null,
  val name: String,
  val curator: Curator?,
  val tags: List<Tag>,
  val images: List<CoverImage>,
  val tracks: PlaylistTrackContainer,
) : MediaItem()

@JsonClass(generateAdapter = true)
data class PlaylistTrackContainer(
  val total: Int,
  val offset: Int,
  val limit: Int,
  @Json(name = "list") val items: List<PlaylistTrack>
)

@JsonClass(generateAdapter = true)
data class PlaylistTrack(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "list",
  override val score: Double? = null,
  val order: Int,
  val createdAt: String,
  val track: Track,
) : MediaItem()
