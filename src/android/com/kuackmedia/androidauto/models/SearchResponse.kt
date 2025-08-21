package com.kuackmedia.androidauto.models

import com.kuackmedia.androidauto.models.MediaItem

data class SearchResponse(
    /** the single “best” item—can be artist, album, playlist, tag or track */
    val best: MediaItem? = null,
    val albums: AlbumResult? = null,
    val artists: ArtistResult? = null,
    val tracks: TrackResult? = null,
    val playlists: PlaylistResult? = null,
    val tags: TagResult? = null,
)

data class AlbumResult (
    val total: Int,
    val offset: Int,
    val limit: Int,
    val list: List<AlbumItem>?
)

data class ArtistResult (
    val total: Int,
    val offset: Int,
    val limit: Int,
    val list: List<Artist>?
)

data class TrackResult (
    val total: Int,
    val offset: Int,
    val limit: Int,
    val list: List<Track>?
)

data class PlaylistResult (
    val total: Int,
    val offset: Int,
    val limit: Int,
    val list: List<PlayListItem>?
)

data class TagResult (
    val total: Int,
    val offset: Int,
    val limit: Int,
    val list: List<Tag>?
)
