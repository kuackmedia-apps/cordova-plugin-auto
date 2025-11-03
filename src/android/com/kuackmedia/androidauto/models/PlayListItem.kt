package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PlayListItem(
  override val id: String,
  override val itemType: String,
  override val itemStyle: String = "grid",
  override val score: Double? = null,
  val name: String,
  val followers: Int,
  val active: Boolean,
  val curator: Curator?,
  val user: Any?,
  val updateDate: Long? = null,
  val createDate: Long? = null,
  val tags: List<Tag>?,
  val images: List<CoverImage>,
  val imageColorInfo: ImageColorInfo? = null,
  var isOffline: Boolean? = false,
) : MediaItem()
