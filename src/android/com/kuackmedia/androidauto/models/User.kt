package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class User(
  val id: Long,
  val name: String,
  val country: String? = null
)
