package com.kuackmedia.androidauto.api

import com.kuackmedia.androidauto.models.AlbumTracks
import com.kuackmedia.androidauto.models.ArtistTracks
import com.kuackmedia.androidauto.models.PlaylistTracks
import com.kuackmedia.androidauto.models.TrackRequest
import com.kuackmedia.androidauto.models.TrackResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Headers
import retrofit2.http.POST
import retrofit2.http.Path

interface MusicApi {
  @GET("albums/{albumId}?limit=100")
  suspend fun getAlbumTracks(@Path("albumId") albumId: String): AlbumTracks

  @GET("playlists/{playListId}?limit=100&offset=0")
  suspend fun getPlayListTracks(@Path("playListId") playListId: String): PlaylistTracks

  @GET("artists/{artistId}/tracks?limit=100")
  suspend fun getArtistTracks(@Path("artistId") artistId: String): ArtistTracks

  @Headers("Content-type: application/json")
  @POST("track-url")
  suspend fun getTrackUrl(@Body trackRequest: TrackRequest): TrackResponse
}
