package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Tag(
  val id: Long,
  val name: String,
  val description: String,
  val isGenre: Boolean,
  val isStation: Boolean,
  val images: List<CoverImage>,       // reuses your Image model
  override val itemType: String,
  val updateDate: Long,
  val imageUpdateDate: Long,
  val amount: Any?,
  val imageColorInfo: ImageColorInfo
) : MediaItem()
