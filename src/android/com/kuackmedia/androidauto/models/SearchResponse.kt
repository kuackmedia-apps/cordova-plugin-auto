package com.kuackmedia.androidauto.models

data class SearchResponse(
    val albums: AlbumResult,
    val artists: ArtistResult,
    val tracks: TrackResult,
    val playlists: PlaylistResult,
    val tags: TagResult,
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