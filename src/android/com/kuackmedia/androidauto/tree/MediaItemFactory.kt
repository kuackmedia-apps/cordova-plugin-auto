package com.kuackmedia.androidauto.tree

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.util.Log
import androidx.media.utils.MediaConstants
import com.kuackmedia.androidauto.models.AlbumItem
import com.kuackmedia.androidauto.models.Artist
import com.kuackmedia.androidauto.models.CoverImage
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.Tag
import com.kuackmedia.androidauto.models.Track
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.io.File


object MediaItemFactory {
  private const val TAG: String = "MediaItemFactory"
  fun parseMediaItems(mediaItem: MediaItem, parentData: String): MediaBrowserCompat.MediaItem? {
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

        result = buildMediaItem(
          title = playlist.name,
          subtitle = if (mediaItem.curator != null) mediaItem.curator.name else "Playlist",
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(getImageUrl(playlist.images)),
          extras = extras
        )
      }

      "album" -> {
        val album = mediaItem as AlbumItem

        result = buildMediaItem(
          title = album.title,
          subtitle = getArtistsNames(album.artists),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(getImageUrl(album.images)),
          extras = extras
        )
      }

      "artist" -> {
        val artist = mediaItem as Artist

        result = this.buildMediaItem(
          title = artist.name,
          subtitle = "Artist",
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(getImageUrl(artist.images)),
          extras = extras
        )
      }

      "tag" -> {
        val tag = mediaItem as Tag

        result = this.buildMediaItem(
          title = tag.name,
          subtitle = tag.description,
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(getImageUrl(tag.images)),
          extras = extras
        )
      }

      "track" -> {
        val track = mediaItem as Track
        val imageUri = if(track.album != null) getImageUrl(track.album.images) else null
        extras.putString("title", track.name)
        extras.putString("artist", getArtistsNames(track.artists))
        extras.putString("album", track.album?.title)
        extras.putString("image", imageUri)
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
          subtitle = getArtistsNames(track.artists),
          mediaId = mediaId,
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = Uri.parse(imageUri),
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

  fun createBrowsable(
    mediaId: String?,
    title: String?,
    iconStringPath: String?,
    context: Context,
  ): MediaBrowserCompat.MediaItem {
    val iconFile = File(context.filesDir, iconStringPath!!)
    val exists = iconFile.exists()
    Log.i(TAG, "createBrowsable Icon $iconStringPath local: $exists")
    val bmp = BitmapFactory.decodeFile(iconFile.absolutePath)

    val description = MediaDescriptionCompat.Builder()
      .setMediaId(mediaId)
      .setTitle(title)
      .setIconBitmap(bmp)
      .build()
    return MediaBrowserCompat.MediaItem(description, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE)
  }

  private fun getImageUrl(images: List<CoverImage>?): String? {
    if (images != null && images.isNotEmpty()) {
      val image = images.last()
      val imageType = image.type
      if (imageType == "create_svg") {
        val imageArray = image.list
        //extract first string url element of imageArray
        if (imageArray != null && imageArray.isNotEmpty()) {
          val urlImage = imageArray.first()
          return urlImage
        }
      } else {
        return image.url
      }
    }
    return null
  }

  private fun getArtistsNames(artists: List<Artist>): String {
    if (artists.isEmpty()) return "Unknown Artist"

    return artists.joinToString(", ") { it.name }
  }
}
