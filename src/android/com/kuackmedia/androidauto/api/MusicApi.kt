package com.kuackmedia.androidauto.api

import com.kuackmedia.androidauto.models.AlbumTracks
import com.kuackmedia.androidauto.models.ArtistAlbumsResponse
import com.kuackmedia.androidauto.models.ArtistPlaylistsResponse
import com.kuackmedia.androidauto.models.ArtistTracks
import com.kuackmedia.androidauto.models.PlaylistTracks
import com.kuackmedia.androidauto.models.PodcastShowResponse
import com.kuackmedia.androidauto.models.RelatedArtistsResponse
import com.kuackmedia.androidauto.models.RelatedTracksByQueueRequest
import com.kuackmedia.androidauto.models.SearchResponse
import com.kuackmedia.androidauto.models.TagTracksResponse
import com.kuackmedia.androidauto.models.Track
import com.kuackmedia.androidauto.models.TrackRequest
import com.kuackmedia.androidauto.models.TrackResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Headers
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface MusicApi {
  @GET("albums/{albumId}")
  suspend fun getAlbumTracks(
    @Path("albumId") albumId: String,
    @Query("limit") limit: Int = 15,
    @Query("offset") offset: Int = 0
  ): AlbumTracks

  @GET("playlists/{playListId}")
  suspend fun getPlayListTracks(
    @Path("playListId") playListId: String,
    @Query("limit") limit: Int = 15,
    @Query("offset") offset: Int = 0
  ): PlaylistTracks

  @GET("artists/{artistId}/tracks")
  suspend fun getArtistTracks(
    @Path("artistId") artistId: String,
    @Query("order") order: String = "popularity",
    @Query("limit") limit: Int = 15,
    @Query("offset") offset: Int = 0
  ): ArtistTracks

  @Headers("Content-type: application/json")
  @GET("tags/{tagId}/playlists")
  suspend fun getTagPlaylists(
    @Path("tagId") tagId: String,
    @Query("limit") limit: Int = 30,
    @Query("offset") offset: Int = 0
  ): TagTracksResponse

  @Headers("Content-type: application/json")
  @POST("track-url")
  suspend fun getTrackUrl(@Body trackRequest: TrackRequest): TrackResponse

  @Headers("Content-type: application/json")
  @GET("search")
  suspend fun search(
    @Query("q") text: String,
    @Query("limit") limit: Int = 4
  ): SearchResponse

  @GET("podcast/{showId}")
  suspend fun getPodcastEpisodes(
    @Path("showId") showId: String,
    @Query("limit") limit: Int = 20,
    @Query("offset") offset: Int = 0
  ): PodcastShowResponse

  // --- New endpoints for Fase 1 ---

  @GET("artists/{artistId}/albums")
  suspend fun getArtistAlbums(
    @Path("artistId") artistId: String,
    @Query("limit") limit: Int = 15,
    @Query("offset") offset: Int = 0
  ): ArtistAlbumsResponse

  @GET("artists/{artistId}/playlists")
  suspend fun getArtistPlaylists(
    @Path("artistId") artistId: String,
    @Query("limit") limit: Int = 15,
    @Query("offset") offset: Int = 0
  ): ArtistPlaylistsResponse

  @GET("artists/{artistId}/related_artists")
  suspend fun getRelatedArtists(
    @Path("artistId") artistId: String,
    @Query("limit") limit: Int = 15
  ): RelatedArtistsResponse

  @GET("tracks/{trackId}/related_tracks")
  suspend fun getRelatedTracks(
    @Path("trackId") trackId: String,
    @Query("limit") limit: Int = 15
  ): ArtistTracks

  @GET("stations/{stationId}/track")
  suspend fun getRadioTracks(
    @Path("stationId") stationId: String,
    @Query("count") count: Int = 15,
    @Query("lastIdAlbumTrack") lastIdAlbumTrack: Long? = null
  ): List<Track>

  @Headers("Content-type: application/json")
  @POST("tracks/related")
  suspend fun getRelatedTracksByQueue(
    @Body request: RelatedTracksByQueueRequest,
    @Query("limit") limit: Int = 10
  ): ArtistTracks

}
