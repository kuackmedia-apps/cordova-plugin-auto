package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PodcastShowResponse(
  val id: String,
  val title: String? = null,
  val author: Any? = null,
  val image: String? = null,
  val ourImage: String? = null,
  val imageUrl: String? = null,
  val episodes: List<PodcastEpisode>? = null,
  val episodesCount: Int? = null,
)
