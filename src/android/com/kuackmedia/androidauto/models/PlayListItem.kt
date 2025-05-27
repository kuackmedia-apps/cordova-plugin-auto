package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PlayListItem(
  val id: Long,
  val name: String,
  val followers: Int,
  val active: Boolean,
  val curator: Curator?,
  val user: Any?,
  val updateDate: Long,
  val createDate: Long,
  val tags: List<Tag>?,
  val images: List<CoverImage>,
  override val itemType: String,
  val imageColorInfo: ImageColorInfo
) : MediaItem()
