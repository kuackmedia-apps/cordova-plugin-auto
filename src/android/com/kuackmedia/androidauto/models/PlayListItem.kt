package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PlayListItem(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  val name: String,
  val followers: Int,
  val active: Boolean,
  val curator: Curator?,
  val user: Any?,
  val updateDate: Long,
  val createDate: Long,
  val tags: List<Tag>?,
  val images: List<CoverImage>,
  val imageColorInfo: ImageColorInfo? = null
) : MediaItem()
