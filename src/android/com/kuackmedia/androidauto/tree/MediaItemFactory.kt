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
import com.kuackmedia.androidauto.models.Tag
import com.kuackmedia.androidauto.models.Track
import com.kuackmedia.androidauto.utils.TextsManager
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File
import kotlin.compareTo


object MediaItemFactory {
  private const val TAG: String = "MediaItemFactory"
  fun parseMediaItems(mediaItem: MediaItem, parentData: String, context: Context): MediaBrowserCompat.MediaItem? {
    var result: MediaBrowserCompat.MediaItem? = null
    val mediaId = "item_" + mediaItem.itemType + "_" + mediaItem.id
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
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
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
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
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
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
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
        val imageUri = if(track.album != null) getImageUri(track.album.images, "album",  track.album.id.toString(), context ) else null
        extras.putString("title", track.name)
        extras.putString("artist", getArtistsNames(track.artists))
        extras.putString("album", track.album?.title)
        extras.putString("image", imageUri.toString())
        extras.putString("length", track.length)
        extras.putString("id", track.id)
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
    val descriptionBuilder = MediaDescriptionCompat.Builder()
      .setMediaId(mediaId)
      .setTitle(title)

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
            uri = FileProvider.getUriForFile(context, "${context.packageName}.cdv.core.file.provider", iconFile)
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
        return Uri.parse(image.url)
      }
    }
    return Uri.parse("https://example.com/default_image.png") // Default image URL
  }

  // Replace existing getLocalPathFromItemTypeAndItemId with this (adds verification)
  private fun getLocalPathFromItemTypeAndItemId(itemType: String?, itemId: String?, context: Context): Uri? {
    val basePath = File(context.filesDir, "img/")
    Log.i(TAG, "getLocalPathFromItemTypeAndItemId called - itemType: $itemType, itemId: $itemId, basePath: ${basePath.absolutePath}")

    if (itemType == null || itemId == null) {
      Log.w(TAG, "getLocalPathFromItemTypeAndItemId - null itemType or itemId")
      return null
    }

    val checks = when (itemType) {
      "track", "album" -> listOf("cover/${itemId}_640.jpg", "cover/${itemId}.jpg", "cover/${itemId}_300.jpg")
      "playlist" -> listOf("playlist/${itemId}_180.png", "playlist/${itemId}.png")
      "artist" -> listOf() // conventionally not local
      else -> listOf("${itemType}/${itemId}.jpg")
    }

    for (relative in checks) {
      val file = File(basePath, relative)
      Log.i(TAG, "Checking local candidate: ${file.absolutePath} (exists=${file.exists()})")
      if (file.exists()) {
        try {
          val authority = "${context.packageName}.cdv.core.file.provider"
          val uri = FileProvider.getUriForFile(context, authority, file)
          Log.i(TAG, "Found file -> content Uri: $uri")

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
      "com.android.car"                         // vendor/system car packages (example)
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
