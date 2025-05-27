package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PlaylistTracks(
  val id: Long,
  val name: String,
  val curator: Curator?,
  val tags: List<Tag>,
  val images: List<CoverImage>,
  val tracks: PlaylistTrackContainer,
  override val itemType: String,
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
  val id: Long,
  val order: Int,
  val createdAt: String,
  val track: Track,
  override val itemType: String
) : MediaItem()
