package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TagTracksResponse(
    val total: Int,
    val offset: Int,
    val limit: Int,
    val list: List<MediaItem>
)
