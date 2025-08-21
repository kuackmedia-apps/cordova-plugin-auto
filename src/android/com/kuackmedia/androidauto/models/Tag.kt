package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Tag(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  override val score: Double? = null,
  val name: String,
  val description: String,
  val isGenre: Boolean,
  val isStation: Boolean,
  val images: List<CoverImage>,
  val updateDate: Long,
  val imageUpdateDate: Long,
  val amount: Any?,
  val imageColorInfo: ImageColorInfo? = null
) : MediaItem()
