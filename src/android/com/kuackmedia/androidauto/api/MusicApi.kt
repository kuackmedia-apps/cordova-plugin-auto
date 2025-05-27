package com.kuackmedia.androidauto.api

import com.kuackmedia.androidauto.models.AlbumItem
import com.kuackmedia.androidauto.models.AlbumTracks
import com.kuackmedia.androidauto.models.HistoryResponse
import com.kuackmedia.androidauto.models.PingResponse
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.PlaylistTracks
import retrofit2.http.GET
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

  @GET("playlist/PlayListTracks/{playListId}")
  suspend fun getPlayListTracks(@Path("playListId") playListId: String): PlaylistTracks

  @GET("auth/ping")
  suspend fun ping(): PingResponse
}
