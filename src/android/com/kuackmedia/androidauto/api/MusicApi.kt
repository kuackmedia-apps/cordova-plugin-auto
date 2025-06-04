package com.kuackmedia.androidauto.api

import com.kuackmedia.androidauto.models.AlbumItem
import com.kuackmedia.androidauto.models.AlbumTracks
import com.kuackmedia.androidauto.models.HistoryResponse
import com.kuackmedia.androidauto.models.PingResponse
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.PlaylistTracks
import com.kuackmedia.androidauto.models.TrackRequest
import com.kuackmedia.androidauto.models.TrackResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Headers
import retrofit2.http.POST
import retrofit2.http.Path

interface MusicApi {
  @GET("album/AlbumTracks/{albumId}")
  suspend fun getAlbumTracks(@Path("albumId") parentId: String): AlbumTracks

  @GET("album/AlbumItem")
  suspend fun getAlbumItem(): AlbumItem

  @GET("history/History")
  suspend fun getHistory(): List<HistoryResponse>

  @GET("playlist/PlayListItem")
  suspend fun getPlayListItem(): PlayListItem
////https://api.prod.kuackmedia.com/api/playlists/33144?limit=15&offset=0
  @GET("playlists/{playListId}?limit=15&offset=0")
  suspend fun getPlayListTracks(@Path("playListId") playListId: String): PlaylistTracks

  @Headers("Content-type: application/json")
  @POST("track-url")
  suspend fun getTrackUrl(@Body trackRequest: TrackRequest): TrackResponse

  @GET("auth/ping")
  suspend fun ping(): PingResponse
}
