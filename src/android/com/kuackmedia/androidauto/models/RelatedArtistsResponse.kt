package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class RelatedArtistsResponse(
    val total: Int = 0,
    val offset: Int = 0,
    val limit: Int = 0,
    val list: List<Artist>
)
