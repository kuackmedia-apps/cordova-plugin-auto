package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class HistoryResponse(
  val id: String,
  val data: HistoryData,
  val type: String,
  val listenedDates: List<Long>,
  val lastDateListened: Long
)

@JsonClass(generateAdapter = true)
data class HistoryData(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  override val score: Double? = null,
  val ttl: Long? = null,
  val upc: String? = null,
  val title: String? = null,
  val lenght: String? = null,
  val name: String? = null,
  val active: Boolean? = null,
  val images: List<CoverImage>? = null,
  val artists: List<Artist>? = null,
  val album: AlbumSummary? = null,
  val subTitle: String? = null,
  val tracksQty: Int? = null,
  val releaseDate: String? = null,
  val releaseType: String? = null,
  val user: User? = null,
  val owner: Boolean? = null,
  val curator: Curator? = null,
  val followers: Int? = null,
  val createDate: Long? = null,
  val updateDate: Long? = null,
  val from: String? = null,
  val isGenre: Boolean? = null,
  val isStation: Boolean? = null,
  val sortDate: Long? = null,
  val amount: Int? = null,
  val description: String? = null,
  val imageColorInfo: ImageColorInfo? = null,
  val options: MixOptions? = null,
  val indice: Int? = null,
  val number: Int? = null,
  val volume: Int? = null,
  val version: String? = null,
  val explicit: Boolean? = null,
  val isPreview: Boolean? = null,
  val playlistId: Int? = null,
  val playlistName: String? = null,
  val playlistTrackId: Int? = null,
  val hasRelatedTracks: Boolean? = null,
  val lastDateListened: Long? = null
) : MediaItem()

@JsonClass(generateAdapter = true)
data class MixOptions(
  val id: String,
  val artists: List<MixArtist>,
  val mixLevel: String,
  val mixPriority: Int,
  val disableSearch: Boolean,
  val emptySelectionText: String,
  val initialArtistsList: List<Any>,
  val disableHeaderUpdate: Boolean? = null,
  val noMoveSelectedToTop: Boolean? = null,
  val updateRelatedArtistsAtTheEnd: Boolean? = null
)

@JsonClass(generateAdapter = true)
data class MixArtist(
  val id: Long,
  val from: String? = null,
  val name: String,
  val rank: Int? = null,
  val images: List<CoverImage>? = null,
  val sortDate: Long? = null,
  val lastDateListened: Long? = null,
  val role: String? = null,
  val score: Double? = null,
  val active: Boolean? = null,
  val itemType: String? = null,
  val imageColorInfo: ImageColorInfo? = null
)

@JsonClass(generateAdapter = true)
data class ContextData(
  val id: String?,
  val type: String?,
  val name: String? = null,
  val title: String? = null,
  val subTitle: String? = null,
  val trackData: Track? = null
)

