package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TracksContainer(
  val total: Int,
  val offset: Int,
  val limit: Int,
  @Json(name = "list") val items: List<Track>
)

@JsonClass(generateAdapter = true)
data class Track(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "list",
  override val score: Double? = null,
  val idAlbumTrack: Long?,
  val isrc: String?,
  val name: String,
  val version: String? = null,
  val length: String,
  val explicit: Boolean?,
  val active: Boolean?,
  val album: AlbumSummary?,
  val artists: List<Artist>,
  val volume: Int?,
  val number: Int?,
  val hasRelatedTracks: Boolean?,
  val imageColorInfo: ImageColorInfo? = null,
  //val context: ContextData? = null,
) : MediaItem()


