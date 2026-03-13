package com.kuackmedia.androidauto.models

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class RelatedTracksByQueueRequest(
    val sources: List<String> = listOf("cm", "stats", "playlists"),
    @Json(name = "album_track_ids") val albumTrackIds: List<Long>,
    @Json(name = "exclude_album_track_ids") val excludeAlbumTrackIds: List<Long> = emptyList(),
    @Json(name = "seed_album_track_ids") val seedAlbumTrackIds: List<Long> = emptyList()
)
