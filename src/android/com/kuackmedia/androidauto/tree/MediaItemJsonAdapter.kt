package com.kuackmedia.androidauto.tree

import com.kuackmedia.androidauto.models.AlbumItem
import com.kuackmedia.androidauto.models.Artist
import com.kuackmedia.androidauto.models.EmptyModel
import com.kuackmedia.androidauto.models.MediaItem
import com.kuackmedia.androidauto.models.PlayListItem
import com.kuackmedia.androidauto.models.Tag
import com.kuackmedia.androidauto.models.Track
import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import com.squareup.moshi.ToJson

class MediaItemJsonAdapter(
  private val moshi: Moshi
) : JsonAdapter<MediaItem>() {
  private val albumAdapter    = moshi.adapter(AlbumItem::class.java)
  private val playlistAdapter = moshi.adapter(PlayListItem::class.java)
  private val trackAdapter      = moshi.adapter(Track::class.java)
  private val tagAdapter      = moshi.adapter(Tag::class.java)
  private val artistAdapter   = moshi.adapter(Artist::class.java)
  private val emptyAdapter    = moshi.adapter(EmptyModel::class.java)

  @FromJson
  override fun fromJson(reader: JsonReader): MediaItem? {
    // 1) Make a peeking copy of the reader at the same position
    val peekReader = reader.peekJson()

    // 2) Read the full JSON object into a Map from the *peek* — this does not
    //    consume the original reader.
    val map = peekReader.readJsonValue() as? Map<*, *>
    peekReader.close()

    // 3) Decide which adapter to delegate to based on the map’s "itemType"
    val type = map?.get("itemType") as? String
    return when (type) {
      "album"    -> albumAdapter.fromJson(reader)
      "playlist" -> playlistAdapter.fromJson(reader)
      "track"      -> trackAdapter.fromJson(reader)
      "tag"      -> tagAdapter.fromJson(reader)
      "artist"   -> artistAdapter.fromJson(reader)
      else       -> emptyAdapter.fromJson(reader)  // fallback for unknown or missing
    }
  }

  @ToJson
  override fun toJson(writer: JsonWriter, value: MediaItem?) {
    moshi.adapter(Any::class.java).toJson(writer, value)
  }
}

