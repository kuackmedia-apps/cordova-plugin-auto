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
  val url: String,
)
