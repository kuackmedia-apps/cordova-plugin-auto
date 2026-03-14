package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PodcastEnclosure(
  val url: String? = null,
  val type: String? = "audio/mpeg",
)

@JsonClass(generateAdapter = true)
data class PodcastEpisode(
  override val id: String,
  override val itemType: String = "podcast_episode",
  override val itemStyle: String = "list",
  override val score: Double? = null,
  val title: String? = null,
  val showId: String? = null,
  val showTitle: String? = null,
  val description: String? = null,
  val datePublished: String? = null,
  val duration: String? = null,
  val durationMs: Long? = null,
  val image: String? = null,
  val ourImage: String? = null,
  val isPodcast: Boolean = true,
  val enclosure: PodcastEnclosure? = null,
) : MediaItem()
