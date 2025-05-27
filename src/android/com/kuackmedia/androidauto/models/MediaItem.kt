package com.kuackmedia.androidauto.models

sealed class MediaItem {
  abstract val id: String
  abstract val itemType: String
  abstract val itemStyle: String
}
