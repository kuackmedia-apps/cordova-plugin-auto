package com.kuackmedia.androidauto.tree

import android.content.Context
import android.content.res.AssetManager
import android.graphics.BitmapFactory
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.util.Log
import androidx.media.utils.MediaConstants
import com.kuackmedia.androidauto.api.MusicApi
import com.kuackmedia.androidauto.media.MusicLibraryService
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.OFFLINE_ROOT
import com.kuackmedia.androidauto.models.AutoNavigationExplorer
import com.kuackmedia.androidauto.models.EmptyModel
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.NavigationData
import com.kuackmedia.androidauto.models.OfflineTrack
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.RecentListened
import com.kuackmedia.androidauto.models.RelatedTracksByQueueRequest
import com.kuackmedia.androidauto.models.Tag
import com.kuackmedia.androidauto.models.Track
import com.kuackmedia.androidauto.utils.TextsManager
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File

object MediaItemTree {
  private const val TAG: String = "MediaItemTree"
  private var treeNodes: MutableMap<String, MediaItemNode> = mutableMapOf()
  private var offlineNodes: MutableMap<String, MediaItemNode> = mutableMapOf()
  private var offlineTitleMap: MutableMap<String, MediaItemNode> = mutableMapOf()
  private var titleMap: MutableMap<String, MediaItemNode> = mutableMapOf()
  private var isInitialized = false
  private lateinit var assets: AssetManager
  private const val ROOT_ID = "[rootID]"
  private lateinit var musicApi: MusicApi


  private class MediaItemNode(val item: MediaBrowserCompat.MediaItem) {
    private val children = mutableListOf<MediaBrowserCompat.MediaItem>()

    fun addChild(childID: String) {
      treeNodes[childID]?.let { node ->
        this.children.add(node.item)
      } ?: Log.w(TAG, "Cannot add child: node with ID $childID not found")
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
    val rootChildren = getChildren(ROOT_ID)
  }

  /**
   * Refresh/reload the entire navigation tree.
   * This clears all existing nodes and rebuilds the tree from files.
   * Use this when navigation data has been updated and needs to be refreshed.
   */
  fun refresh(context: Context) {
    // Clear all existing data
    treeNodes.clear()
    offlineNodes.clear()
    offlineTitleMap.clear()
    titleMap.clear()

    // Reset initialization flag
    isInitialized = false

    // Reinitialize with current musicApi
    if (::musicApi.isInitialized) {
      initialize(context, musicApi)
    } else {
      Log.e(TAG, "[REFRESH] Cannot refresh - musicApi not initialized")
    }
  }

  private fun loadNavigationData(context: Context): List<NavigationData> {
    val jsonFile = File(context.filesDir, "AUTO_NAVIGATION")

    if (!jsonFile.exists()) {
      Log.e(TAG, "El archivo AUTO_NAVIGATION no existe.")
      return emptyList()
    }

    try {
      val jsonArray = jsonFile.readText(Charsets.UTF_8)

      // Validate that file is not empty
      if (jsonArray.isBlank()) {
        Log.w(TAG, "File AUTO_NAVIGATION is empty")
        return emptyList()
      }

      // Validate that content looks like JSON
      val trimmed = jsonArray.trim()
      if (!trimmed.startsWith("[") && !trimmed.startsWith("{")) {
        Log.e(TAG, "File AUTO_NAVIGATION does not contain valid JSON format")
        jsonFile.delete()
        return emptyList()
      }

      val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()
      val listType = Types.newParameterizedType(List::class.java, NavigationData::class.java)
      val adapter: JsonAdapter<List<NavigationData>> = moshi.adapter(listType)
      val navigationData = adapter.fromJson(jsonArray)

      return navigationData ?: emptyList()

    } catch (e: java.io.EOFException) {
      Log.e(TAG, "Incomplete JSON file AUTO_NAVIGATION (EOF): ${e.message}", e)
      return emptyList()
    } catch (e: com.squareup.moshi.JsonDataException) {
      Log.e(TAG, "JSON data exception in AUTO_NAVIGATION: ${e.message}", e)
      return emptyList()
    } catch (e: com.squareup.moshi.JsonEncodingException) {
      Log.e(TAG, "JSON encoding exception in AUTO_NAVIGATION: ${e.message}", e)
      return emptyList()
    } catch (e: Exception) {
      Log.e(TAG, "Unexpected error parsing AUTO_NAVIGATION: ${e.message}", e)
      return emptyList()
    }
  }

  private fun loadNavigationDataChildren(context: Context, fileName: String):
    List<MediaBrowserCompat.MediaItem> {
    var result: List<MediaBrowserCompat.MediaItem>? = emptyList()
    val jsonFile = File(context.filesDir, fileName)

    if (!jsonFile.exists()) {
      Log.e(TAG, "File $fileName does not exist")
      return emptyList()
    }

    try {
      val jsonArray = jsonFile.readText(Charsets.UTF_8)

      // Validate that file is not empty
      if (jsonArray.isBlank()) {
        Log.w(TAG, "File $fileName is empty")
        return emptyList()
      }

      // Validate that content looks like JSON
      val trimmed = jsonArray.trim()
      if (!trimmed.startsWith("[") && !trimmed.startsWith("{")) {
        Log.e(TAG, "File $fileName does not contain valid JSON format")
        jsonFile.delete()
        return emptyList()
      }

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
      "RECENT_LISTENED_AUTO" -> {
        // Parse as raw list first, then parse each item from its own JSON string.
        // This avoids JsonReader state corruption when an adapter fails mid-parse on a nested object.
        val anyAdapter = Moshi.Builder().build().adapter(Any::class.java)
        val listAnyType = Types.newParameterizedType(List::class.java, Any::class.java)
        val listAnyAdapter: JsonAdapter<List<Any>> = Moshi.Builder().build().adapter(listAnyType)
        val rawItems: List<Any>? = listAnyAdapter.fromJson(jsonArray)

        val itemAdapter: JsonAdapter<RecentListened> = moshi.adapter(RecentListened::class.java)
        val items = mutableListOf<RecentListened>()
        val total = rawItems?.size ?: 0
        rawItems?.forEachIndexed { idx, rawItem ->
          try {
            val itemJson = anyAdapter.toJson(rawItem)
            val item = itemAdapter.fromJson(itemJson)
            if (item != null) items.add(item)
          } catch (e: Exception) {
            val rawMap = rawItem as? Map<*, *>
            val rawType = rawMap?.get("type") as? String
            val rawData = rawMap?.get("data") as? Map<*, *>
            val rawItemType = rawData?.get("itemType") as? String
            Log.w(TAG, "[RECENT_LISTENED] Skipping item[$idx] type=$rawType itemType=$rawItemType: ${e.message}")
          }
        }
        result = items
          .filter { it.data !is EmptyModel }
          .filter { it.data.itemType != "track" }
          .mapNotNull {
            try {
              MediaItemFactory.parseMediaItems(it.data, "", context)
            } catch (e: Exception) {
              Log.w(TAG, "Failed to parse recent listened item: ${e.message}")
              null
            }
          }
        if (result.isNotEmpty()) {
          result.forEach { item ->
            val mediaId = item.mediaId ?: return@forEach
            treeNodes[mediaId] = MediaItemNode(item)
            treeNodes[mediaId]?.let { node ->
              titleMap[item.description.title.toString()] = node
            }
            treeNodes["RECENT_LISTENED_AUTO_MENU"]?.addChild(mediaId)
          }
        }
      }

      "AUTO_NAVIGATION_LIBRARY" -> {
        val listType = Types.newParameterizedType(List::class.java, AutoNavigationExplorer::class.java)
        val adapter: JsonAdapter<List<AutoNavigationExplorer>> = moshi.adapter(listType)
        val libraryItems: List<AutoNavigationExplorer>? = adapter.fromJson(jsonArray)

        if (libraryItems != null && libraryItems.isNotEmpty()) {
          libraryItems.forEach { libraryItem ->
            val libraryMediaItem = MediaItemFactory.createBrowsable(
              mediaId = libraryItem.mediaId,
              title = libraryItem.text,
              iconStringPath = libraryItem.icon,
              itemStyle = "LIST",
              context = context
            )

            val libraryMediaId = libraryMediaItem.mediaId ?: return@forEach
            treeNodes[libraryMediaId] = MediaItemNode(libraryMediaItem)
            treeNodes[libraryMediaId]?.let { node ->
              titleMap[libraryMediaItem.description.title.toString()] = node
            }
            treeNodes["AUTO_NAVIGATION_LIBRARY_MENU"]?.addChild(libraryMediaId)

            libraryItem.items.forEach { item ->
              try {
                val categoryMediaItem = MediaItemFactory.parseMediaItems(item, "", context)
                if (categoryMediaItem != null) {
                  val categoryMediaId = categoryMediaItem.mediaId ?: return@forEach
                  treeNodes[categoryMediaId] = MediaItemNode(categoryMediaItem)
                  treeNodes[categoryMediaId]?.let { node ->
                    titleMap[categoryMediaItem.description.title.toString()] = node
                  }
                  treeNodes[libraryMediaId]?.addChild(categoryMediaId)
                }
              } catch (e: Exception) {
                Log.w(TAG, "Failed to parse library category item: ${e.message}")
              }
            }
          }
        }
      }
    "AUTO_NAVIGATION_HOME" -> {
        val listType = Types.newParameterizedType(List::class.java, AutoNavigationExplorer::class.java)
        val adapter: JsonAdapter<List<AutoNavigationExplorer>> = moshi.adapter(listType)
        val homeItems: List<AutoNavigationExplorer>? = adapter.fromJson(jsonArray)

        if (homeItems != null && homeItems.isNotEmpty()) {
          homeItems.forEach { homeItem ->
            val homeMediaItem = MediaItemFactory.createBrowsable(
              mediaId = homeItem.mediaId,
              title = homeItem.text,
              iconStringPath = homeItem.icon,
              itemStyle = "LIST",
              context = context
            )

            val homeMediaId = homeMediaItem.mediaId ?: return@forEach
            treeNodes[homeMediaId] = MediaItemNode(homeMediaItem)
            treeNodes[homeMediaId]?.let { node ->
              titleMap[homeMediaItem.description.title.toString()] = node
            }
            treeNodes["AUTO_NAVIGATION_HOME_MENU"]?.addChild(homeMediaId)

            homeItem.items.forEach { item ->
              try {
                val categoryMediaItem = MediaItemFactory.parseMediaItems(item, "", context)
                if (categoryMediaItem != null) {
                  val categoryMediaId = categoryMediaItem.mediaId ?: return@forEach
                  treeNodes[categoryMediaId] = MediaItemNode(categoryMediaItem)
                  treeNodes[categoryMediaId]?.let { node ->
                    titleMap[categoryMediaItem.description.title.toString()] = node
                  }
                  treeNodes[homeMediaId]?.addChild(categoryMediaId)
                }
              } catch (e: Exception) {
                Log.w(TAG, "Failed to parse home category item: ${e.message}")
              }
            }
          }
        }
      }
    "AUTO_NAVIGATION_LIBRARY_OFFLINE" -> {
      val listType = Types.newParameterizedType(List::class.java, MediaItem::class.java)
      val adapter: JsonAdapter<List<MediaItem>> = moshi.adapter(listType)
      val items: List<MediaItem>? = adapter.fromJson(jsonArray)


      result = items
        ?.filter { it !is EmptyModel }
        ?.mapNotNull {
          try {
            MediaItemFactory.parseMediaItems(it, "", context)
          } catch (e: Exception) {
            Log.w(TAG, "Failed to parse offline item: ${e.message}")
            null
          }
        }

      //set all result items listStyle LIST
      if (result != null && result.isNotEmpty()) {
        result.forEach { item ->
          val mediaId = item.mediaId ?: return@forEach
          offlineNodes[mediaId] = MediaItemNode(item)
          offlineNodes[mediaId]?.let { node ->
            offlineTitleMap[item.description.title.toString()] = node
          }
          treeNodes["AUTO_NAVIGATION_LIBRARY_OFFLINE"]?.addChild(mediaId)
        }
      }
    }

      "AUTO_NAVIGATION_EXPLORER" -> {
        val listType = Types.newParameterizedType(List::class.java, MediaItem::class.java)
        val adapter: JsonAdapter<List<MediaItem>> = moshi.adapter(listType)
        val items: List<MediaItem>? = adapter.fromJson(jsonArray)
        result = items
          ?.filter { it !is EmptyModel }
          ?.mapNotNull {
            try {
              MediaItemFactory.parseMediaItems(it, "", context)
            } catch (e: Exception) {
              Log.w(TAG, "Failed to parse explorer item: ${e.message}")
              null
            }
          }
        if (result != null && result.isNotEmpty()) {
          result.forEach { item ->
            val mediaId = item.mediaId ?: return@forEach
            treeNodes[mediaId] = MediaItemNode(item)
            treeNodes[mediaId]?.let { node ->
              titleMap[item.description.title.toString()] = node
            }
            treeNodes["AUTO_NAVIGATION_EXPLORER_MENU"]?.addChild(mediaId)
          }
        }
      }
    }

    return result ?: emptyList()

    } catch (e: com.squareup.moshi.JsonDataException) {
      Log.e(TAG, "JSON data exception in file $fileName: ${e.message}", e)
      return emptyList()
    } catch (e: com.squareup.moshi.JsonEncodingException) {
      Log.e(TAG, "JSON encoding exception in file $fileName: ${e.message}", e)
      return emptyList()
    } catch (e: java.io.EOFException) {
      Log.e(TAG, "Incomplete JSON file $fileName (EOF): ${e.message}", e)
      return emptyList()
    } catch (e: Exception) {
      Log.e(TAG, "Unexpected error parsing file $fileName: ${e.message}", e)
      return emptyList()
    }
  }


  fun getOfflineMediaItem(context: Context): MediaBrowserCompat.MediaItem {
    val extras = Bundle()
    extras.putInt(
      MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
      MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
    )
    val iconStringPath = "img/auto-offline.png"
    val iconFile = File(context.filesDir, iconStringPath)
    val exists = iconFile.exists()
    val bmp = BitmapFactory.decodeFile(iconFile.absolutePath)

    val offlineItem = MediaBrowserCompat.MediaItem(
      MediaDescriptionCompat.Builder()
        .setMediaId(OFFLINE_ROOT)
        .setTitle(TextsManager.getText("no_internet_connection"))
        .setSubtitle(TextsManager.getText("go_to_library"))
        .setExtras(extras)
        .setIconBitmap(bmp)
        .build(),
      MediaBrowserCompat.MediaItem.FLAG_BROWSABLE
    )
    return offlineItem
  }

  /**
   * Returns a MediaItem that prompts the user to log in via the mobile app.
   * Shown when navigation data is empty (user not logged in or data not initialized).
   */
  fun getLoginRequiredMediaItem(context: Context): MediaBrowserCompat.MediaItem {
    val extras = Bundle()
    extras.putInt(
      MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
      MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
    )
    val iconStringPath = "img/auto-library.png"
    val iconFile = File(context.filesDir, iconStringPath)
    val bmp = if (iconFile.exists()) BitmapFactory.decodeFile(iconFile.absolutePath) else null

    // Get localized text with fallback (AUTO_TEXTS may not exist if user never logged in)
    var loginMessage = TextsManager.getText("no_credential_message")
    if (loginMessage.isEmpty()) {
      loginMessage = "Log in to see your music"
      Log.w(TAG, "[getLoginRequiredMediaItem] no_credential_message not found, using fallback")
    }

    // Use FLAG_PLAYABLE so Android Auto doesn't try to browse into it
    // This will show the item but clicking it won't navigate anywhere
    val loginItem = MediaBrowserCompat.MediaItem(
      MediaDescriptionCompat.Builder()
        .setMediaId("[login_required]")
        .setTitle(loginMessage)
        .setExtras(extras)
        .apply { if (bmp != null) setIconBitmap(bmp) }
        .build(),
      MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
    )
    return loginItem
  }

  /**
   * Checks if user is logged in by verifying refresh token exists.
   */
  fun isUserLoggedIn(context: Context): Boolean {
    val prefs = context.getSharedPreferences("NativeStorage", Context.MODE_PRIVATE)
    val refreshToken = prefs.getString("REFRESH_TOKEN_KEY", null)?.replace("\"", "")
    val isLoggedIn = !refreshToken.isNullOrEmpty()
    return isLoggedIn
  }

  fun getOfflineItems(): List<MediaBrowserCompat.MediaItem> {
    val offlineItems = mutableListOf<MediaBrowserCompat.MediaItem>()
   // offlineItems.add(offlineItem)
    //get All children
    offlineNodes.forEach { (_, node) ->
      offlineItems.add(node.item)
    }
    return offlineItems
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

    navigationData.forEach {
      try {
        val mediaId = it.fileName + "_MENU"
        val style = if (it.fileName == "RECENT_LISTENED_AUTO") "LIST" else "GRID"
        treeNodes[mediaId] =
          MediaItemNode(
            MediaItemFactory.createBrowsable(
              title = it.text,
              mediaId = mediaId,
              iconStringPath = it.icon,
              itemStyle = style,
              context = context
            )
          )
        treeNodes[ROOT_ID]?.addChild(mediaId)

        loadNavigationDataChildren(context, it.fileName)
      } catch (e: Exception) {
        Log.e(TAG, "Error building navigation menu item: ${e.message}")
      }
    }
    try {
      loadNavigationDataChildren(context, "AUTO_NAVIGATION_LIBRARY_OFFLINE")
    } catch (e: Exception) {
      Log.e(TAG, "Error loading offline navigation: ${e.message}")
    }
  }

  fun getItem(id: String): MediaBrowserCompat.MediaItem? {
    return treeNodes[id]?.item
  }

  fun getParentId(mediaId: String, parentId: String = ROOT_ID): String? {
    val parentNode = treeNodes[parentId] ?: return null
    for (child in parentNode.getChildren()) {
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

  suspend fun search(query: String, context: Context): MutableList<MediaBrowserCompat.MediaItem> {
    // new grouped implementation with headers
    val matches = mutableListOf<MediaBrowserCompat.MediaItem>()
   // Log.d(TAG, "Received search query: $query")
    // search over tree nodes titles
    val normalizedQuery = normalizeSearchText(query)
    if (!MusicLibraryService.isNetworkEnabled(context)) {
      if (normalizedQuery.isNotEmpty()) {
        offlineTitleMap.forEach { (title, node) ->
          // Log.d(TAG, "Searching in title: $title")
          if (normalizeSearchText(title).contains(normalizedQuery)) {
            matches.add(node.item)
          }
        }
      }
    } else {

      if (normalizedQuery.isNotEmpty()) {
        titleMap.forEach { (title, node) ->
          // Log.d(TAG, "Searching in title: $title")
          if (normalizeSearchText(title).contains(normalizedQuery)) {
            matches.add(node.item)
          }
        }
      }
      val result = this.musicApi.search(query)
      // Best Result
      result.best?.let { bestItem ->
        val header = MediaItemFactory.buildMediaItem(
          title = TextsManager.getText("best_result").ifEmpty { "Best Result" },
          subtitle = "",
          mediaId = "header_best",
          flags = 0
        )
        matches.add(header)
        parseSearchResult(matches, bestItem, context)
      }

      // Artistas
      result.artists?.list?.takeIf { it.isNotEmpty() }?.let { list ->
        val header = MediaItemFactory.buildMediaItem(
          title = TextsManager.getText("artists"),
          subtitle = "",
          mediaId = "header_artists",
          flags = 0
        )
        matches.add(header)
        list.forEach { parseSearchResult(matches, it, context) }
      }

      // Albums
      result.albums?.list?.takeIf { it.isNotEmpty() }?.let { list ->
        val header = MediaItemFactory.buildMediaItem(
          title = TextsManager.getText("albums"),
          subtitle = "",
          mediaId = "header_albums",
          flags = 0
        )
        matches.add(header)
        list.forEach { parseSearchResult(matches, it, context) }
      }

      // Playlists
      result.playlists?.list?.takeIf { it.isNotEmpty() }?.let { list ->
        val extras = android.os.Bundle().apply { putBoolean("isHeader", true) }
        val header = MediaItemFactory.buildMediaItem(
          title = TextsManager.getText("playlists"),
          subtitle = "",
          mediaId = "header_playlists",
          flags = 0,
          extras = extras
        )
        matches.add(header)
        list.forEach { parseSearchResult(matches, it, context) }
      }

      // Tags
      result.tags?.list?.takeIf { it.isNotEmpty() }?.let { list ->
        val extras = android.os.Bundle().apply { putBoolean("isHeader", true) }
        val header = MediaItemFactory.buildMediaItem(
          title = TextsManager.getText("tags"),
          subtitle = "",
          mediaId = "header_tags",
          flags = 0,
          extras = extras
        )
        matches.add(header)
        list.forEach { parseSearchResult(matches, it, context) }
      }

      // Tracks
      result.tracks?.list?.takeIf { it.isNotEmpty() }?.let { list ->
        val extras = android.os.Bundle().apply { putBoolean("isHeader", true) }
        val header = MediaItemFactory.buildMediaItem(
          title = TextsManager.getText("tracks"),
          subtitle = "",
          mediaId = "header_tracks",
          flags = 0,
          extras = extras
        )
        matches.add(header)
        list.forEach { parseSearchResult(matches, it, context) }
      }
    }

    return matches
  }

  fun parseSearchResult(matches: MutableList<MediaBrowserCompat.MediaItem>, mediaItem: MediaItem, context: Context) {
    val parentData = when (mediaItem.itemType) {
      "track" -> {
        val track = mediaItem as Track
        val trackJson = try {
          val adapter = MediaItemJsonAdapter(
            Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
          )
          adapter.toJson(track)
        } catch (e: Exception) { "{}" }
        "{\"type\":\"TRACK_RADIO\",\"id\":\"${track.id}\",\"trackData\":$trackJson}"
      }
      else -> ""
    }
    val parsedItem = MediaItemFactory.parseMediaItems(mediaItem, parentData, context)
    if(parsedItem != null) {
      val mediaId = parsedItem.mediaId ?: return
      treeNodes[mediaId] = MediaItemNode(parsedItem)
      treeNodes[mediaId]?.let { node ->
        titleMap[parsedItem.description.title.toString()] = node
      }
      matches.add(parsedItem)
    }
  }

  fun getRootItem(): MediaBrowserCompat.MediaItem? {
    return treeNodes[ROOT_ID]?.item
  }

  fun getChildren(id: String): List<MediaBrowserCompat.MediaItem> {
    return treeNodes[id]?.getChildren() ?: listOf()
  }

  private fun loadOfflineTracksByMediaTypeMediaId(
    mediaType: String,
    itemId: String,
    context: Context
  ): List<MediaBrowserCompat.MediaItem> {
    val result: MutableList<MediaBrowserCompat.MediaItem> = mutableListOf()

    // Read and parse OFFLINE_TRACKS file
    val jsonFile = File(context.filesDir, "OFFLINE_TRACKS")

    if (!jsonFile.exists()) {
      Log.e(TAG, "[OFFLINE_TRACKS_FILE_NOT_FOUND] File OFFLINE_TRACKS does not exist at: ${jsonFile.absolutePath}")
      return emptyList()
    }

    try {
      val jsonContent = jsonFile.readText(Charsets.UTF_8)

      // Parse JSON as Map<String, OfflineTrack>
      val moshi = Moshi.Builder()
        .add(MediaItem::class.java, MediaItemJsonAdapter(
          Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()
        ))
        .add(KotlinJsonAdapterFactory())
        .build()

      val mapType = Types.newParameterizedType(
        Map::class.java,
        String::class.java,
        OfflineTrack::class.java
      )
      val adapter: JsonAdapter<Map<String, OfflineTrack>> = moshi.adapter(mapType)

      val offlineTracksMap: Map<String, OfflineTrack>? = adapter.fromJson(jsonContent)

      if (offlineTracksMap == null) {
        Log.e(TAG, "[OFFLINE_TRACKS_PARSE_FAILED] Failed to parse OFFLINE_TRACKS file - result is null")
        return emptyList()
      }

      // Extract itemId from parentId (e.g., "item_album_38048" -> "38048")
      val idParts = itemId.split("_")

      val targetId = if (idParts.size > 2) idParts[2].toIntOrNull() else null

      if (targetId == null) {
        Log.w(TAG, "[OFFLINE_TRACKS_INVALID_ID] Could not extract valid ID from parentId: $itemId, idParts: $idParts")
        return emptyList()
      }

      // Build parentData so tapped tracks know their parent context (ALBUM/PLAYLIST)
      val cleanItemId = if (idParts.size > 2) idParts[2] else itemId
      val parentTitle = getItem(itemId)?.description?.title?.toString() ?: ""
      val parentData = "{" +
        " \"id\": \"$cleanItemId\",\n" +
        "  \"type\": \"${mediaType.uppercase()}\",\n" +
        "  \"name\": \"$parentTitle\"" +
        "}"

      // Filter tracks based on mediaType and itemId
      offlineTracksMap.forEach { (trackId, offlineTrack) ->
        val shouldInclude = when (mediaType) {
          "album" -> offlineTrack.albumItemsOffline?.contains(targetId) == true
          "playlist" -> offlineTrack.playlistsItemsOffline?.contains(targetId) == true
          else -> {
            Log.w(TAG, "[OFFLINE_TRACKS_UNKNOWN_TYPE] Unknown mediaType: $mediaType for track $trackId")
            false
          }
        }

        if (shouldInclude) {
          val mediaItem = MediaItemFactory.parseMediaItems(offlineTrack.trackData, parentData, context)
          if (mediaItem != null) {
            // Register in tree so onPlayFromMediaId can find the track
            val mid = mediaItem.mediaId
            if (mid != null) {
              treeNodes[mid] = MediaItemNode(mediaItem)
            }
            result.add(mediaItem)
          } else {
            Log.w(TAG, "[OFFLINE_TRACKS_PARSE_FAILED] Failed to parse track '${offlineTrack.trackData.name}' " +
                       "(ID: ${offlineTrack.trackData.id}) into MediaItem")
          }
        }
      }

    } catch (e: Exception) {
      Log.e(TAG, "[OFFLINE_TRACKS_ERROR] Exception occurred while loading offline tracks: ${e.message}", e)
      Log.e(TAG, "[OFFLINE_TRACKS_STACK_TRACE] ${e.stackTraceToString()}")
    }

    return result
  }
  suspend fun getRemoteChildren(parentId: String, context: Context): List<MediaBrowserCompat.MediaItem> {
    val parent = getItem(parentId)
    val mediaType = parent?.description?.extras?.getString("media_type")
    var result: List<MediaBrowserCompat.MediaItem> = emptyList()

    // Check network availability
    if (!MusicLibraryService.isNetworkEnabled(context)) {
      if (mediaType != null) {
        val offlineTracks = loadOfflineTracksByMediaTypeMediaId(mediaType, parentId, context)
        if (offlineTracks.isNotEmpty()) {
          // Add Play All / Shuffle action items (same as online flow)
          val idParts = parentId.split("_")
          val cleanItemId = if (idParts.size > 2) idParts[2] else parentId
          val parentTitle = parent?.description?.title?.toString() ?: ""
          val actionItems = buildActionItems(mediaType, cleanItemId, parentTitle)
          return actionItems + offlineTracks
        }
      }

      return emptyList()
    }

    //receive item_playlist_5232 return 5232
    val idParts = parentId.split("_")
    val itemId = if (idParts.size > 2) idParts[2] else parentId;
    when (mediaType) {
      "playlist" -> {
        val parentData = "{" +
          " \"id\": \"${itemId}\",\n" +
          "  \"type\": \"PLAYLIST\",\n" +
          "  \"name\": \"${parent.description.title}\"" +
          "}"
        val tracks = this.musicApi.getPlayListTracks(itemId).tracks.items.mapNotNull {
          val mediaItem = MediaItemFactory.parseMediaItems(it.track, parentData, context)
          if (mediaItem != null) {
            val mid = mediaItem.mediaId ?: return@mapNotNull null
            treeNodes[mid] = MediaItemNode(mediaItem)
          }
          mediaItem
        }
        val actionItems = buildActionItems("playlist", itemId, parent.description.title?.toString() ?: "")
        result = actionItems + tracks
      }

      "album" -> {
        val parentData = "{" +
          " \"id\": \"${itemId}\",\n" +
          "  \"type\": \"ALBUM\",\n" +
          "  \"name\": \"${parent.description.title}\"" +
          "}"
        val tracks = this.musicApi.getAlbumTracks(itemId).tracks.items.mapNotNull {
          val mediaItem = MediaItemFactory.parseMediaItems(it, parentData, context)
          if (mediaItem != null) {
            val mid = mediaItem.mediaId ?: return@mapNotNull null
            treeNodes[mid] = MediaItemNode(mediaItem)
          }
          mediaItem
        }
        val actionItems = buildActionItems("album", itemId, parent.description.title?.toString() ?: "")
        result = actionItems + tracks
      }

      "artist" -> {
        val parentData = "{" +
          " \"id\": \"${itemId}\",\n" +
          "  \"type\": \"ARTIST\",\n" +
          "  \"name\": \"${parent.description.title}\"" +
          "}"
        val tracks = this.musicApi.getArtistTracks(itemId).list.mapNotNull {
          val mediaItem = MediaItemFactory.parseMediaItems(it, parentData, context)
          if (mediaItem != null) {
            val mid = mediaItem.mediaId ?: return@mapNotNull null
            treeNodes[mid] = MediaItemNode(mediaItem)
          }
          mediaItem
        }
        val actionItems = buildActionItems("artist", itemId, parent.description.title?.toString() ?: "")
        result = actionItems + tracks
      }

      "tag" -> {
        result = this.musicApi.getTagPlaylists(itemId).list.mapNotNull {
          val parentData = "{" +
              " \"id\": \"${itemId}\",\n" +
              "  \"type\": \"PLAYLIST\",\n" +
              "  \"name\": \"${parent.description.title}\"" +
              "}"
          val mediaItem = MediaItemFactory.parseMediaItems(it, parentData, context)
          if (mediaItem != null) {
            val mediaId = "item_" + it.itemType + "_" + it.id
            treeNodes[mediaId] = MediaItemNode(mediaItem)
            treeNodes[ROOT_ID]?.addChild(mediaId)
          }
          mediaItem
        }
      }

      "podcast" -> {
        try {
          val response = this.musicApi.getPodcastEpisodes(itemId)
          result = response.episodes?.mapNotNull { episode ->
            try {
              val mediaItem = MediaItemFactory.parseMediaItems(episode, "", context)
              if (mediaItem != null) {
                val epMediaId = mediaItem.mediaId ?: return@mapNotNull null
                treeNodes[epMediaId] = MediaItemNode(mediaItem)
              }
              mediaItem
            } catch (e: Exception) {
              Log.e(TAG, "[PODCAST_EPISODES_ERROR] Episode ${episode.id}: ${e.message}", e)
              null
            }
          } ?: emptyList()
        } catch (e: Exception) {
          Log.e(TAG, "[PODCAST_EPISODES_ERROR] Exception fetching episodes for podcast $itemId: ${e.message}", e)
          result = emptyList()
        }
      }
    }
    return result
  }

  /**
   * Builds a track radio queue: the selected track + related tracks.
   * Returns MediaBrowserCompat.MediaItem list ready for QueueManager.
   */
  // --- Paginated fetch methods for 2+15 incremental loading ---

  suspend fun getAlbumTracksPage(
    albumId: String,
    parentData: String,
    context: Context,
    limit: Int = 15,
    offset: Int = 0
  ): List<MediaBrowserCompat.MediaItem> {
    val response = musicApi.getAlbumTracks(albumId, limit = limit, offset = offset)
    return response.tracks.items.mapNotNull { track ->
      val mediaItem = MediaItemFactory.parseMediaItems(track, parentData, context)
      if (mediaItem != null) {
        val mid = mediaItem.mediaId ?: return@mapNotNull null
        treeNodes[mid] = MediaItemNode(mediaItem)
      }
      mediaItem
    }
  }

  suspend fun getPlaylistTracksPage(
    playlistId: String,
    parentData: String,
    context: Context,
    limit: Int = 15,
    offset: Int = 0
  ): List<MediaBrowserCompat.MediaItem> {
    val response = musicApi.getPlayListTracks(playlistId, limit = limit, offset = offset)
    return response.tracks.items.mapNotNull { playlistTrack ->
      val mediaItem = MediaItemFactory.parseMediaItems(playlistTrack.track, parentData, context)
      if (mediaItem != null) {
        val mid = mediaItem.mediaId ?: return@mapNotNull null
        treeNodes[mid] = MediaItemNode(mediaItem)
      }
      mediaItem
    }
  }

  suspend fun getArtistTracksPage(
    artistId: String,
    parentData: String,
    context: Context,
    limit: Int = 15,
    offset: Int = 0,
    order: String = "popularity"
  ): List<MediaBrowserCompat.MediaItem> {
    val response = musicApi.getArtistTracks(artistId, order = order, limit = limit, offset = offset)
    return response.list.mapNotNull { track ->
      val mediaItem = MediaItemFactory.parseMediaItems(track, parentData, context)
      if (mediaItem != null) {
        val mid = mediaItem.mediaId ?: return@mapNotNull null
        treeNodes[mid] = MediaItemNode(mediaItem)
      }
      mediaItem
    }
  }

  suspend fun getStationRadioPage(
    stationId: String,
    parentData: String,
    context: Context,
    count: Int = 15,
    lastIdAlbumTrack: Long? = null
  ): List<MediaBrowserCompat.MediaItem> {
    val tracks = musicApi.getRadioTracks(stationId, count, lastIdAlbumTrack)
    return tracks.mapNotNull { track ->
      val mediaItem = MediaItemFactory.parseMediaItems(track, parentData, context)
      if (mediaItem != null) {
        val mid = mediaItem.mediaId ?: return@mapNotNull null
        treeNodes[mid] = MediaItemNode(mediaItem)
      }
      mediaItem
    }
  }

  suspend fun getRelatedTracksPage(
    trackId: String,
    parentData: String,
    context: Context,
    limit: Int = 15
  ): List<MediaBrowserCompat.MediaItem> {
    val response = musicApi.getRelatedTracks(trackId, limit)
    return response.list.mapNotNull { track ->
      val mediaItem = MediaItemFactory.parseMediaItems(track, parentData, context)
      if (mediaItem != null) {
        val mid = mediaItem.mediaId ?: return@mapNotNull null
        treeNodes[mid] = MediaItemNode(mediaItem)
      }
      mediaItem
    }
  }

  suspend fun getTrackRadioContinuation(
    albumTrackIds: List<Long>,
    excludeAlbumTrackIds: List<Long>,
    seedAlbumTrackIds: List<Long>,
    parentData: String,
    context: Context,
    limit: Int = 15
  ): List<MediaBrowserCompat.MediaItem> {
    val request = RelatedTracksByQueueRequest(
      albumTrackIds = albumTrackIds,
      excludeAlbumTrackIds = excludeAlbumTrackIds,
      seedAlbumTrackIds = seedAlbumTrackIds
    )
    val response = musicApi.getRelatedTracksByQueue(request, limit = limit)
    return response.list.mapNotNull { track ->
      val mediaItem = MediaItemFactory.parseMediaItems(track, parentData, context)
      if (mediaItem != null) {
        val mid = mediaItem.mediaId ?: return@mapNotNull null
        treeNodes[mid] = MediaItemNode(mediaItem)
      }
      mediaItem
    }
  }

  /**
   * Builds Play and Shuffle action items for album/playlist drill-down.
   * These appear at the top of the track list.
   */
  private fun buildActionItems(
    mediaType: String,
    itemId: String,
    itemName: String
  ): List<MediaBrowserCompat.MediaItem> {
    val playText = TextsManager.getText("play").ifEmpty { "Play" }
    val shuffleText = TextsManager.getText("shuffle").ifEmpty { "Shuffle" }

    val playExtras = Bundle().apply {
      putInt(
        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
      )
    }
    val shuffleExtras = Bundle().apply {
      putInt(
        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
      )
    }

    val playItem = MediaItemFactory.buildMediaItem(
      title = "\u25B6 $playText",
      subtitle = itemName,
      mediaId = "play_all:${mediaType}:${itemId}",
      flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
      extras = playExtras
    )
    val shuffleItem = MediaItemFactory.buildMediaItem(
      title = "\u21C6 $shuffleText",
      subtitle = itemName,
      mediaId = "shuffle:${mediaType}:${itemId}",
      flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
      extras = shuffleExtras
    )
    return listOf(playItem, shuffleItem)
  }

  private fun normalizeSearchText(text: CharSequence?): String {
    if (text.isNullOrEmpty() || text.trim().length == 1) {
      return ""
    }
    return "$text".trim().lowercase()
  }
}
