package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Artist(
  val id: Long,
  val name: String,
  val images: List<CoverImage>?,
  val active: Boolean?,
  val role: String?,
  override val itemType: String,
  val score: Double?,                   // null in your payload
  val imageColorInfo: Any?              // null in your payload
) : MediaItem()
