package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TrackRequest(
  val idAlbumTrack: String,
  val idTrack: String,
  val forceDevice: Boolean,
  val useCloudFront: Boolean,
  val forcePreview: Boolean,
  val extraLife: Boolean,
)

@JsonClass(generateAdapter = true)
data class TrackResponse(
  val idTrack: Double,
  val idAlbumTrack: Double,
  val idVideo: Double?,
  val isPreview: Boolean,
  val signedUrl: String,
  val rights: List<Right>,
)

@JsonClass(generateAdapter = true)
data class Right(
  val idDist: Double,
  val idLabel: Double,
  val hadRight: Boolean,
)
