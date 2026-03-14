package com.kuackmedia.androidauto.media

data class QueueLoadingState(
  val contentType: String,
  val contentId: String,
  val contentName: String = "",
  val parentData: String = "",
  var currentOffset: Int = 0,
  var lastIdAlbumTrack: Long? = null,
  var excludeAlbumTrackIds: MutableList<Long> = mutableListOf(),
  var seedAlbumTrackIds: MutableList<Long> = mutableListOf(),
  var hasMore: Boolean = true,
  var isLoading: Boolean = false
)
