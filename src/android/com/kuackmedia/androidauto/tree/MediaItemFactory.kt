package com.kuackmedia.androidauto.tree

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.util.Log
import com.kuackmedia.androidauto.models.AlbumItem
import com.kuackmedia.androidauto.models.Artist
import com.kuackmedia.androidauto.models.CoverImage
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.Tag
import com.kuackmedia.androidauto.models.Track
import org.apache.cordova.media.AudioHandler.TAG
import java.io.File


object MediaItemFactory {
  fun parseMediaItems(mediaItem: MediaItem): MediaBrowserCompat.MediaItem? {
    var result: MediaBrowserCompat.MediaItem? = null
    when (mediaItem.itemType) {
      "playlist" -> {
        val playlist = mediaItem as PlayListItem
        val extras = Bundle().apply {
          putString("media_type", "playlist")
        }

        result = buildMediaItem(
          title = playlist.name,
          subtitle = if (mediaItem.curator != null) mediaItem.curator.name else "Playlist",
          mediaId = playlist.id.toString(),
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(playlist.images[0].url),
          extras = extras
        )
      }

      "album" -> {
        val album = mediaItem as AlbumItem
        val extras = Bundle().apply {
          putString("media_type", "album") // or "album", "track", etc.
        }
        result = buildMediaItem(
          title = album.title,
          subtitle = getArtistsNames(album.artists),
          mediaId = album.id.toString(),
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(album.images[0].url),
          extras = extras
        )
      }

      "artist" -> {
        val artist = mediaItem as Artist
        val extras = Bundle().apply {
          putString("media_type", "artist") // or "album", "track", etc.
        }
        result = this.buildMediaItem(
          title = artist.name,
          subtitle = "Artist",
          mediaId = artist.id.toString(),
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(getImageUrl(artist.images)),
          extras = extras
        )
      }

      "tag" -> {
        val tag = mediaItem as Tag
        val extras = Bundle().apply {
          putString("media_type", "tag") // or "album", "track", etc.
        }
        result = this.buildMediaItem(
          title = tag.name,
          subtitle = tag.description,
          mediaId = tag.id.toString(),
          flags = MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
          imageUri = Uri.parse(getImageUrl(tag.images)),
          extras = extras
        )
      }

      "track" -> {
        val track = mediaItem as Track
        val extras = Bundle().apply {
          putString("media_type", "track") // or "album", "track", etc.
        }
        result = this.buildMediaItem(
          title = track.name,
          subtitle = getArtistsNames(track.artists),
          mediaId = track.id.toString(),
          flags = MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
          imageUri = if(track.album != null) Uri.parse(getImageUrl(track.album.images)) else null,
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
    if (images !== null && images.isNotEmpty()) {
      val image = images.first()
      return image.url
    } else return null
  }

  private fun getArtistsNames(artists: List<Artist>): String {
    if (artists.isEmpty()) return "Unknown Artist"

    return artists.joinToString(", ") { it.name }
  }
}
