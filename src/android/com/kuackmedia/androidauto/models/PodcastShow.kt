package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PodcastShow(
  override val id: String,
  override val itemType: String = "podcast",
  override val itemStyle: String = "list",
  override val score: Double? = null,
  val title: String? = null,
  val name: String? = null,
  val author: Any? = null,
  val image: String? = null,
  val ourImage: String? = null,
  val imageUrl: String? = null,
  val episodesCount: Int? = null,
  val description: String? = null,
) : MediaItem()
