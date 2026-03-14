package com.kuackmedia.androidauto.tree

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.util.Log
import androidx.core.content.FileProvider
import androidx.media.utils.MediaConstants
import com.kuackmedia.androidauto.models.AlbumItem
import com.kuackmedia.androidauto.models.Artist
import com.kuackmedia.androidauto.models.CoverImage
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.PodcastEpisode
import com.kuackmedia.androidauto.models.PodcastShow
import com.kuackmedia.androidauto.models.Tag
import com.kuackmedia.androidauto.models.Track
import com.kuackmedia.androidauto.utils.TextsManager
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File
import kotlin.compareTo


object MediaItemFactory {
  private const val TAG: String = "MediaItemFactory"

  /**
   * Sanitizes an ID string by removing trailing ".0" from Double-parsed numbers.
   * JSON numbers parsed via readJsonValue() become Double (e.g., 9206567 -> "9206567.0").
   */
  fun sanitizeId(id: String): String {
    return if (id.endsWith(".0")) id.dropLast(2) else id
  }

  fun parseMediaItems(mediaItem: MediaItem, parentData: String, context: Context): MediaBrowserCompat.MediaItem? {
    var result: MediaBrowserCompat.MediaItem? = null
    val cleanId = sanitizeId(mediaItem.id)
    val mediaId = "item_" + mediaItem.itemType + "_" + cleanId
    var extras = Bundle()

    extras.putString("parentData", parentData)
    extras.putString("media_type", mediaItem.itemType)
    if (mediaItem.itemStyle == "grid") {
      extras.putInt(
        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_CATEGORY_GRID_ITEM
      )
    } else {
      extras.putInt(
        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
      )
    }

    when (mediaItem.itemType) {
      "playlist" -> {
        val playlist = mediaItem as PlayListItem

        var localURI = getImageUri(playlist.images, "playlist", playlist.id.toString(), context);
        if (localURI == null) {
         // localURI = getImageUrl(playlist.images, "playlist", playlist.id.toString(), context);
        }

        result = buildMediaItem(
          title = playlist.name,
          subtitle = TextsManager.getText("playlist"),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = localURI,
          extras = extras
        )
      }

      "album" -> {
        val album = mediaItem as AlbumItem

        result = buildMediaItem(
          title = album.title,
          subtitle = TextsManager.getText("album") + " - " +getArtistsNames(album.artists),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = getImageUri(album.images, "album", album.id.toString(), context),
          extras = extras
        )
      }

      "artist" -> {
        val artist = mediaItem as Artist
        //LOG artist IMAGES
        Log.i(TAG, "Artist images: ${artist.images}")
        result = this.buildMediaItem(
          title = artist.name,
          subtitle = TextsManager.getText("artist"),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = getImageUri(artist.images, "artist", artist.id.toString(), context),
          extras = extras
        )
      }

      "tag" -> {
        val tag = mediaItem as Tag

        result = this.buildMediaItem(
          title = tag.name,
          subtitle = TextsManager.getText("tag"),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = getImageUri(tag.images, "tag", tag.id.toString(), context),
          extras = extras
        )
      }

      "track" -> {
        val track = mediaItem as Track
        val cleanAlbumId = if (track.album != null) sanitizeId(track.album.id.toString()) else null
        val imageUri = if(track.album != null) getImageUri(track.album.images, "album", cleanAlbumId, context ) else null
        extras.putString("title", track.name)
        extras.putString("artist", getArtistsNames(track.artists))
        extras.putString("album", track.album?.title)
        extras.putString("image", imageUri.toString())
        extras.putString("length", track.length)
        extras.putString("id", cleanId)
        extras.putString("idAlbumTrack", track.idAlbumTrack.toString())

        val mediaItemAdapter = MediaItemJsonAdapter(
          Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()
        )
        extras.putString("track", mediaItemAdapter.toJson(track))

        result = this.buildMediaItem(
          title = track.name,
          subtitle = TextsManager.getText("track") +  " " + getArtistsNames(track.artists),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = if(track.album != null) getImageUri(track.album.images, "album",  track.album.id.toString(), context ) else null,
          extras = extras
        )
      }

      "artist_radio" -> {
        val artist = mediaItem as Artist
        result = this.buildMediaItem(
          title = artist.name,
          subtitle = TextsManager.getText("station") + " - " + TextsManager.getText("artist"),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = getImageUri(artist.images, "artist", artist.id.toString(), context),
          extras = extras
        )
      }

      "radio" -> {
        val tag = mediaItem as Tag
        result = this.buildMediaItem(
          title = tag.name,
          subtitle = TextsManager.getText("station"),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = getImageUri(tag.images, "tag", tag.id.toString(), context),
          extras = extras
        )
      }

      "radio_track" -> {
        val track = mediaItem as Track
        val cleanAlbumId = if (track.album != null) sanitizeId(track.album.id.toString()) else null
        val imageUri = if(track.album != null) getImageUri(track.album.images, "album", cleanAlbumId, context) else null

        extras.putString("title", track.name)
        extras.putString("artist", getArtistsNames(track.artists))
        extras.putString("album", track.album?.title)
        extras.putString("image", imageUri.toString())
        extras.putString("length", track.length)
        extras.putString("id", cleanId)
        extras.putString("idAlbumTrack", track.idAlbumTrack.toString())

        val mediaItemAdapter = MediaItemJsonAdapter(
          Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()
        )
        extras.putString("track", mediaItemAdapter.toJson(track))

        result = this.buildMediaItem(
          title = track.name,
          subtitle = TextsManager.getText("station") + " - " + TextsManager.getText("track"),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = imageUri,
          extras = extras
        )
      }

      "podcast" -> {
        val podcast = mediaItem as PodcastShow
        val displayTitle = podcast.title ?: podcast.name ?: "Podcast"
        val imageUrl = podcast.ourImage ?: podcast.image ?: podcast.imageUrl
        val imageUri = if (imageUrl != null) {
          getPodcastImageUri(podcast.id, imageUrl, context)
        } else null

        result = this.buildMediaItem(
          title = displayTitle,
          subtitle = "Podcast",
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = imageUri,
          extras = extras
        )
      }

      "podcast_episode", "podcastEpisode" -> {
        val episode = mediaItem as PodcastEpisode
        val displayTitle = episode.title ?: "Episode"
        val subtitle = episode.duration ?: episode.showTitle ?: "Podcast"
        val imageUrl = episode.ourImage ?: episode.image
        val imageUri = if (imageUrl != null) Uri.parse(imageUrl) else null

        extras.putString("title", displayTitle)
        extras.putString("artist", episode.showTitle ?: "Podcast")
        extras.putString("album", episode.showTitle ?: "Podcast")
        extras.putString("image", imageUri?.toString() ?: "")
        extras.putString("id", cleanId)
        extras.putString("showId", episode.showId ?: "")
        extras.putString("enclosure_url", episode.enclosure?.url ?: "")
        extras.putString("isPodcast", "true")
        if (episode.durationMs != null) {
          extras.putLong("durationMs", episode.durationMs)
        }
        extras.putString("length", episode.duration ?: "0")

        result = this.buildMediaItem(
          title = displayTitle,
          subtitle = subtitle,
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = imageUri,
          extras = extras
        )
      }
    }

    return result
  }

  fun buildMediaItem(
    title: String,
    subtitle: String,
    mediaId: String,
    imageUri: Uri? = null,
    flags: Int,
    extras: Bundle? = null
  ): MediaBrowserCompat.MediaItem {
    val descriptionBuilder = MediaDescriptionCompat.Builder()
      .setMediaId(mediaId)
      .setTitle(title)
      .setSubtitle(subtitle)
      .setExtras(extras)

    if (imageUri != null) {
      descriptionBuilder.setIconUri(imageUri)
    }

    return MediaBrowserCompat.MediaItem(descriptionBuilder.build(), flags)
  }
  // Replace createBrowsable implementation to use content Uri and logs (avoid decodeFile)
  fun createBrowsable(
    mediaId: String?,
    title: String?,
    iconStringPath: String?,
    itemStyle: String?,
    context: Context,
  ): MediaBrowserCompat.MediaItem {

    val iconFile = File(context.filesDir, iconStringPath!!)
    val exists = iconFile.exists()
    Log.i(TAG, "createBrowsable Icon $iconStringPath local: $exists")
    val bmp = BitmapFactory.decodeFile(iconFile.absolutePath)

    val descriptionBuilder = MediaDescriptionCompat.Builder()
      .setMediaId(mediaId)
      .setTitle(title)
      .setIconBitmap(bmp);

    if (!iconStringPath.isNullOrBlank()) {
      try {
        var uri: Uri? = null
        if (iconStringPath.startsWith("content://") || iconStringPath.startsWith("file://")) {
          uri = Uri.parse(iconStringPath)
          Log.i(TAG, "createBrowsable: iconStringPath already a URI: $uri")
        } else {
          val iconFile = File(context.filesDir, iconStringPath)
          Log.i(TAG, "createBrowsable: checking local file ${iconFile.absolutePath} (exists=${iconFile.exists()})")
          if (iconFile.exists()) {
            uri = FileProvider.getUriForFile(context, "${context.packageName}.auto.file.provider", iconFile)
            Log.i(TAG, "createBrowsable: content Uri for file: $uri")
            // grant permission to likely clients (debug)
            grantReadPermissionToCarApps(context, uri)
          } else {
            Log.w(TAG, "createBrowsable: local icon file not found: ${iconFile.absolutePath}")
          }
        }
        if (uri != null) {
          descriptionBuilder.setIconUri(uri)
        }
      } catch (ex: Exception) {
        Log.w(TAG, "createBrowsable: error creating uri for iconStringPath=$iconStringPath: ${ex.message}", ex)
      }
    } else {
      Log.i(TAG, "createBrowsable: no iconStringPath for $title")
    }

    if (itemStyle != null && itemStyle == "LIST") {
      val extras = Bundle()
      extras.putInt(
        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
      )
      descriptionBuilder.setExtras(extras)
    }

    if (itemStyle != null && itemStyle == "GRID") {
      val extras = Bundle()
      extras.putInt(
        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_SINGLE_ITEM,
        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_CATEGORY_GRID_ITEM
      )
      descriptionBuilder.setExtras(extras)
    }

    return MediaBrowserCompat.MediaItem(descriptionBuilder.build(), MediaBrowserCompat.MediaItem.FLAG_BROWSABLE)
  }

  private fun getPodcastImageUri(podcastId: String, imageUrl: String, context: Context): Uri? {
    // Check local podcast image first
    val basePath = File(context.filesDir, "img/podcast/")
    val extensions = listOf("jpg", "jpeg", "png")
    for (ext in extensions) {
      val localFile = File(basePath, "$podcastId.$ext")
      if (localFile.exists()) {
        try {
          val authority = "${context.packageName}.auto.file.provider"
          val uri = FileProvider.getUriForFile(context, authority, localFile)
          grantReadPermissionToCarApps(context, uri)
          return uri
        } catch (e: Exception) {
          Log.w(TAG, "getPodcastImageUri: FileProvider failed for ${localFile.absolutePath}: ${e.message}")
        }
      }
    }
    // Fallback to remote URL
    return Uri.parse(imageUrl)
  }

  private fun getImageUri(images: List<CoverImage>?, itemType: String?, itemId: String?, context: Context): Uri? {

    Log.i(TAG, "getImageUrl  $itemType  - $itemId")

    // First try to get local path
    val localPath = getLocalPathFromItemTypeAndItemId(itemType, itemId, context)
    if (localPath != null) {
      Log.i(TAG, "getImageUrl  found localPath $localPath")
      return localPath
    }
 //   Log.i(TAG, "getImageUrl  localPath $localPath")

    if (images != null && images.isNotEmpty()) {
      val image = images.last()
      val imageType = image.type
      if (imageType == "create_svg") {
        val imageArray = image.list
        //extract first string url element of imageArray
        if (imageArray != null && imageArray.isNotEmpty()) {
          val urlImage = imageArray.first()
          return Uri.parse(urlImage)
        }
      } else {
        val url = image.url
        // Convert file:// URIs to content:// via FileProvider (Android Auto can't read file:// URIs)
        if (url != null && url.startsWith("file://")) {
          val filePath = Uri.parse(url).path
          if (filePath != null) {
            val file = File(filePath)
            if (file.exists()) {
              try {
                val authority = "${context.packageName}.auto.file.provider"
                val contentUri = FileProvider.getUriForFile(context, authority, file.canonicalFile)
                Log.i(TAG, "getImageUri: converted file:// to content:// URI: $contentUri")
                grantReadPermissionToCarApps(context, contentUri)
                return contentUri
              } catch (e: Exception) {
                Log.w(TAG, "getImageUri: FileProvider failed for $filePath: ${e.message}")
              }
            } else {
              Log.w(TAG, "getImageUri: local file not found: $filePath")
            }
          }
        }
        return Uri.parse(url)
      }
    }
    return Uri.parse("https://example.com/default_image.png") // Default image URL
  }

  // Replace existing getLocalPathFromItemTypeAndItemId with this (adds verification)
  private fun getLocalPathFromItemTypeAndItemId(itemType: String?, itemId: String?, context: Context): Uri? {
    // Use canonical path to avoid symlink issues (/data/data vs /data/user/0)
    val basePathRaw = File(context.filesDir, "img/")
    val basePath = try {
      basePathRaw.canonicalFile
    } catch (e: Exception) {
      Log.w(TAG, "Could not get canonical path, using absolute: ${e.message}")
      basePathRaw
    }
    Log.i(TAG, "getLocalPathFromItemTypeAndItemId called - itemType: $itemType, itemId: $itemId, basePath: ${basePath.absolutePath}")

    if (itemType == null || itemId == null) {
      Log.w(TAG, "getLocalPathFromItemTypeAndItemId - null itemType or itemId")
      return null
    }

    val checks = when (itemType) {
      "track", "album" -> listOf("cover/${itemId}_640.jpg", "cover/${itemId}.jpg", "cover/${itemId}_180.jpg")
      "playlist" -> listOf("playlist/${itemId}_180.png", "playlist/${itemId}.png")
      "artist" -> listOf() // conventionally not local
      "tag" -> listOf("tag/${itemId}_180.png")
      else -> listOf("${itemType}/${itemId}.jpg")
    }

    for (relative in checks) {
      val fileRaw = File(basePath, relative)
      // Use canonical file to resolve symlinks consistently with FileProvider
      val fileCanonical = try {
        fileRaw.canonicalFile
      } catch (e: Exception) {
        fileRaw
      }
      Log.i(TAG, "Checking local candidate: ${fileCanonical.absolutePath} (exists=${fileCanonical.exists()})")
      if (fileCanonical.exists()) {
        val authority = "${context.packageName}.auto.file.provider"

        // Try with canonical file first, then fallback to raw file if it fails
        // This handles edge cases with symlinks on different Android versions
        val filesToTry = listOf(fileCanonical, fileRaw).distinct()

        for (file in filesToTry) {
          try {
            val uri = FileProvider.getUriForFile(context, authority, file)
            Log.i(TAG, "Found file -> content Uri: $uri (using path: ${file.absolutePath})")

            // Quick runtime verification: can we open it via ContentResolver?
            try {
              context.contentResolver.openInputStream(uri)?.use { stream ->
                val firstByte = stream.read()
                if (firstByte >= 0) {
                  Log.i(TAG, "ContentResolver can open Uri: $uri (firstByte=$firstByte)")
                } else {
                  Log.w(TAG, "ContentResolver opened Uri but no data: $uri")
                }
              }
            } catch (ioEx: Exception) {
              Log.w(TAG, "ContentResolver failed to open Uri $uri: ${ioEx.message}", ioEx)
            }

            // Try to grant READ permission to likely car/auto packages (for debugging)
            grantReadPermissionToCarApps(context, uri)

            return uri
          } catch (ex: Exception) {
            Log.w(TAG, "FileProvider.getUriForFile failed for ${file.absolutePath}: ${ex.message}", ex)
            // Continue to try the next file path variant
          }
        }
      }
    }

    Log.i(TAG, "No local image found for itemType: $itemType, itemId: $itemId")
    return null
  }

  // Helper: grant read permission to known car/auto packages if installed
  private fun grantReadPermissionToCarApps(context: Context, uri: Uri) {
    val candidates = listOf(
      "com.google.android.projection.gearhead", // Android Auto older package
      "com.google.android.gms",                 // Play Services (may proxy)
    )
    val pm = context.packageManager
    for (pkg in candidates) {
      try {
        pm.getPackageInfo(pkg, 0)
        context.grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        Log.i(TAG, "grantReadPermissionToCarApps: granted READ for $uri to $pkg")
      } catch (ex: Exception) {
        Log.d(TAG, "grantReadPermissionToCarApps: package $pkg not present")
      }
    }
  }
  private fun getArtistsNames(artists: List<Artist>): String {
    if (artists.isEmpty()) return "Unknown Artist"

    return artists.joinToString(", ") { it.name }
  }
}
