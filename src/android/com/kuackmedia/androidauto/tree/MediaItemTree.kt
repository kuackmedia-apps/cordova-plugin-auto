package com.kuackmedia.androidauto.tree

import android.content.Context
import android.content.res.AssetManager
import android.support.v4.media.MediaBrowserCompat
import android.util.Log
import com.kuackmedia.androidauto.api.MusicApi
import com.kuackmedia.androidauto.models.AutoNavigationExplorer
import com.kuackmedia.androidauto.models.EmptyModel
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.NavigationData
import com.kuackmedia.androidauto.models.RecentListened
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File

object MediaItemTree {
  private const val TAG: String = "MediaItemTree"
  private var treeNodes: MutableMap<String, MediaItemNode> = mutableMapOf()
  private var titleMap: MutableMap<String, MediaItemNode> = mutableMapOf()
  private var isInitialized = false
  private lateinit var assets: AssetManager
  private const val ROOT_ID = "[rootID]"
  private lateinit var musicApi: MusicApi


  private class MediaItemNode(val item: MediaBrowserCompat.MediaItem) {
    private val children = mutableListOf<MediaBrowserCompat.MediaItem>()

    fun addChild(childID: String) {
      this.children.add(treeNodes[childID]!!.item)
    }

    fun getChildren(): List<MediaBrowserCompat.MediaItem> {
      return children.toList()
    }
  }

  fun initialize(context: Context, musicApi: MusicApi) {
    this.assets = context.assets
    this.musicApi = musicApi

    if (isInitialized) return
    isInitialized = true

    val navigationData = loadNavigationData(context)
    buildNavigationMenu(navigationData, context)
  }

  private fun loadNavigationData(context: Context): List<NavigationData> {
    var navigationData: List<NavigationData>?
    val jsonFile = File(context.filesDir, "AUTO_NAVIGATION")
    Log.i(TAG, "Ruta del archivo JSON: AUTO_NAVIGATION - " + jsonFile.absolutePath)

    if (!jsonFile.exists()) {
      Log.e(TAG, "El archivo AUTO_NAVIGATION no existe.")
      return emptyList()
    }

    val jsonArray = jsonFile.readText(Charsets.UTF_8)
    val moshi = Moshi.Builder()
      .add(KotlinJsonAdapterFactory())
      .build()
    val listType = Types.newParameterizedType(List::class.java, NavigationData::class.java)
    val adapter: JsonAdapter<List<NavigationData>> = moshi.adapter(listType)
    navigationData = adapter.fromJson(jsonArray)
    val safeList: List<NavigationData> = navigationData ?: emptyList()

    return safeList
  }

  private fun loadNavigationDataChildren(context: Context, fileName: String):
    List<MediaBrowserCompat.MediaItem> {
    Log.i(TAG, "Trying to parse $fileName")

    var result: List<MediaBrowserCompat.MediaItem>? = emptyList()
    val jsonFile = File(context.filesDir, fileName)

    if (!jsonFile.exists()) {
      Log.e(TAG, "File $fileName does not exist")
      return emptyList()
    }

    val jsonArray = jsonFile.readText(Charsets.UTF_8)

    val mediaItemAdapter = MediaItemJsonAdapter(
      Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()
    )
    val moshi = Moshi.Builder()
      .add(MediaItem::class.java, mediaItemAdapter)
      .add(KotlinJsonAdapterFactory())
      .build()

    when (fileName) {
      "RECENT_LISTENED" -> {
        val listType = Types.newParameterizedType(List::class.java, RecentListened::class.java)
        val adapter: JsonAdapter<List<RecentListened>> = moshi.adapter(listType)
        val items: List<RecentListened>? = adapter.fromJson(jsonArray)
        result = items
          ?.filter { it.data !is EmptyModel }
          ?.map { MediaItemFactory.parseMediaItems(it.data, "")!! }
        if (result != null && result.isNotEmpty()) {
          result.forEach {
            treeNodes[it.mediaId!!] = MediaItemNode(it)
            titleMap[it.description.title.toString()] = treeNodes[it.mediaId!!]!!
            treeNodes["RECENT_LISTENED_MENU"]?.addChild(it.mediaId!!)
          }
        }
      }

      "AUTO_NAVIGATION_LIBRARY" -> {
        val listType = Types.newParameterizedType(List::class.java, AutoNavigationExplorer::class.java)
        val adapter: JsonAdapter<List<AutoNavigationExplorer>> = moshi.adapter(listType)
        val libraryItems: List<AutoNavigationExplorer>? = adapter.fromJson(jsonArray)

        if (libraryItems != null && libraryItems.isNotEmpty()) {
          libraryItems.forEach {
            val libraryMediaItem = MediaItemFactory.createBrowsable(
              mediaId = it.text,
              title = it.text,
              iconStringPath = it.icon,
              itemStyle = "LIST",
              context = context
            )

            treeNodes[libraryMediaItem.mediaId!!] = MediaItemNode(libraryMediaItem)
            titleMap[libraryMediaItem.description.title.toString()] = treeNodes[libraryMediaItem.mediaId]!!
            treeNodes["AUTO_NAVIGATION_LIBRARY_MENU"]?.addChild(libraryMediaItem.mediaId!!)

            it.items.forEach {
              val categoryMediaItem = MediaItemFactory.parseMediaItems(it, "")!!
              treeNodes[categoryMediaItem.mediaId!!] = MediaItemNode(categoryMediaItem)
              titleMap[categoryMediaItem.description.title.toString()] = treeNodes[categoryMediaItem.mediaId]!!
              treeNodes[libraryMediaItem.mediaId]?.addChild(categoryMediaItem.mediaId!!)
            }
          }
        }
      }

      "AUTO_NAVIGATION_EXPLORER" -> {
        val listType = Types.newParameterizedType(List::class.java, MediaItem::class.java)
        val adapter: JsonAdapter<List<MediaItem>> = moshi.adapter(listType)
        val items: List<MediaItem>? = adapter.fromJson(jsonArray)
        result = items
          ?.filter { it !is EmptyModel }
          ?.map { MediaItemFactory.parseMediaItems(it, "")!! }
        if (result != null && result.isNotEmpty()) {
          result.forEach {
            treeNodes[it.mediaId!!] = MediaItemNode(it)
            titleMap[it.description.title.toString()] = treeNodes[it.mediaId!!]!!
            treeNodes["AUTO_NAVIGATION_EXPLORER_MENU"]?.addChild(it.mediaId!!)
          }
        }
      }
    }

    return result ?: emptyList()
  }

  private fun buildNavigationMenu(navigationData: List<NavigationData>, context: Context) {
    treeNodes[ROOT_ID] =
      MediaItemNode(
        MediaItemFactory.buildMediaItem(
          title = "Root Folder",
          subtitle = "",
          mediaId = ROOT_ID,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
        )
      )

    // Add hardcoded playlists menu
    val playlistsMenuId = "PLAYLISTS_MENU"
    treeNodes[playlistsMenuId] =
      MediaItemNode(
        MediaItemFactory.buildMediaItem(
          title = "Playlists",
          subtitle = "Featured playlists",
          mediaId = playlistsMenuId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
        )
      )
    treeNodes[ROOT_ID]!!.addChild(playlistsMenuId)

    // Add hardcoded playlists
    addHardcodedPlaylists(context, playlistsMenuId)

    // Add existing navigation data
    navigationData.forEach {
      val mediaId = it.fileName + "_MENU"
      treeNodes[mediaId] =
        MediaItemNode(
          MediaItemFactory.createBrowsable(
            title = it.text,
            mediaId = mediaId,
            iconStringPath = it.icon,
            itemStyle = "GRID",
            context = context
          )
        )
      treeNodes[ROOT_ID]!!.addChild(mediaId)

      loadNavigationDataChildren(context, it.fileName)
    }
  }

  private fun addHardcodedPlaylists(context: Context, parentId: String) {
    // Create three hardcoded playlists
    val playlists = listOf(
      Triple("playlist_1", "Featured Tracks", "Our featured music collection"),
      Triple("playlist_2", "Sample Music", "Sample tracks for demonstration"),
      Triple("playlist_3", "Favorites", "Your favorite tracks")
    )

    playlists.forEach { (id, title, description) ->
      val playlistId = "hardcoded_$id"
      val playlistItem = MediaItemFactory.buildMediaItem(
        title = title,
        subtitle = description,
        mediaId = playlistId,
        flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE
      )

      treeNodes[playlistId] = MediaItemNode(playlistItem)
      treeNodes[parentId]!!.addChild(playlistId)

      // Add the sample track to each playlist
      val trackId = "${playlistId}_track_1"
      val extras = Bundle().apply {
        putString("media_uri", "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")
        putString("title", "SoundHelix Song 1")
        putString("artist", "T. Schürger")
        putString("album", "SoundHelix Samples")
      }

      val trackItem = MediaItemFactory.buildMediaItem(
        title = "SoundHelix Song 1",
        subtitle = "T. Schürger - SoundHelix Samples",
        mediaId = trackId,
        flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
        extras = extras
      )

      treeNodes[trackId] = MediaItemNode(trackItem)
      treeNodes[playlistId]!!.addChild(trackId)
    }
  }

  fun getItem(id: String): MediaBrowserCompat.MediaItem? {
    return treeNodes[id]?.item
  }

  fun getParentId(mediaId: String, parentId: String = ROOT_ID): String? {
    for (child in treeNodes[parentId]!!.getChildren()) {
      if (child.mediaId == mediaId) {
        return parentId
      } else if (child.isBrowsable == true) {
        val nextParentId = getParentId(mediaId, child.mediaId.toString())
        if (nextParentId != null) {
          return nextParentId
        }
      }
    }
    return null
  }

  suspend fun search(query: String): MutableList<MediaBrowserCompat.MediaItem> {
    val matches: MutableList<MediaBrowserCompat.MediaItem> = mutableListOf()
    val result = this.musicApi.search(query)

    result.tracks.list!!.forEach { track ->
      this.parseSearchResult(matches, track)
    }

    result.playlists.list!!.forEach { playlist ->
      this.parseSearchResult(matches, playlist)
    }

    result.artists.list!!.forEach { artist ->
      this.parseSearchResult(matches, artist)
    }

    result.albums.list!!.forEach { album ->
      this.parseSearchResult(matches, album)
    }

    result.tags.list!!.forEach { tag ->
      this.parseSearchResult(matches, tag)
    }

    return matches
  }

  fun parseSearchResult(matches: MutableList<MediaBrowserCompat.MediaItem>, mediaItem: MediaItem) {
    val parsedItem = MediaItemFactory.parseMediaItems(mediaItem, "")
    if(parsedItem !== null) {
      treeNodes[parsedItem.mediaId!!] = MediaItemNode(parsedItem)
      titleMap[parsedItem.description.title.toString()] = treeNodes[parsedItem.mediaId!!]!!
      matches.add(parsedItem)
    }
  }

  fun getRootItem(): MediaBrowserCompat.MediaItem {
    return treeNodes[ROOT_ID]!!.item
  }

  fun getChildren(id: String): List<MediaBrowserCompat.MediaItem> {
    return treeNodes[id]?.getChildren() ?: listOf()
  }

  suspend fun getRemoteChildren(parentId: String): List<MediaBrowserCompat.MediaItem> {
    val parent = getItem(parentId)
    val mediaType = parent?.description?.extras?.getString("media_type")
    var result: List<MediaBrowserCompat.MediaItem> = emptyList()

    Log.i(TAG, "Trying to load remote children for $parentId - $mediaType")

    //receive item_playlist_5232 return 5232
    val idParts = parentId.split("_")
    val itemId = if (idParts.size > 2) idParts[2] else parentId;
    Log.i(TAG, "Trying to load remote children for $itemId - $mediaType")
    when (mediaType) {
      "playlist" -> {
        result = this.musicApi.getPlayListTracks(itemId).tracks.items.mapNotNull {
          val parentData = "{" +
            " \"id\": $itemId,\n" +
            "  \"type\": \"PLAYLIST\",\n" +
            "  \"name\": ${parent.description.title}" +
            "}"
          MediaItemFactory.parseMediaItems(it.track, parentData)
        }
      }

      "album" -> {
        result =  this.musicApi.getAlbumTracks(itemId).tracks.items.mapNotNull {
          val parentData = "{" +
            " \"id\": $itemId,\n" +
            "  \"type\": \"ALBUM\",\n" +
            "  \"name\": ${parent.description.title}" +
            "}"
          MediaItemFactory.parseMediaItems(it, parentData)
        }
      }

      "artist" -> {
        result =  this.musicApi.getArtistTracks(itemId).list.mapNotNull {
          val parentData = "{" +
            " \"id\": $itemId,\n" +
            "  \"type\": \"ARTIST\",\n" +
            "  \"name\": ${parent.description.title}" +
            "}"
          MediaItemFactory.parseMediaItems(it, parentData)
        }
      }

      "tag" -> {
        result =  this.musicApi.getTagTracks(itemId).list.map {
          val parentData = "{" +
              " \"id\": $itemId,\n" +
              "  \"type\": \"PLAYLIST\",\n" +
              "  \"name\": ${parent.description.title}" +
              "}"
          val mediaItem = MediaItemFactory.parseMediaItems(it, parentData)
          val mediaId = "item_" + it.itemType + "_" + it.id
          treeNodes[mediaId] =
            MediaItemNode(mediaItem!!)
          treeNodes[ROOT_ID]!!.addChild(mediaId)

          mediaItem
        }
      }
    }
    Log.i(TAG, "Remote children for $parentId - $mediaType size is ${result.size}")
    return result
  }

  private fun normalizeSearchText(text: CharSequence?): String {
    if (text.isNullOrEmpty() || text.trim().length == 1) {
      return ""
    }
    return "$text".trim().lowercase()
  }
}
