package com.kuackmedia.androidauto.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Curator(
  val id: Long,
  // Nullable a propósito: el backend devuelve curators con name=null y Moshi es
  // ESTRICTO — un solo item así hacía fallar el parseo del archivo COMPLETO y dejaba la
  // pestaña vacía (HOME quedó vacío en el Xiaomi 12 Pro por $[0].items[9].curator.name).
  // Nadie lee este campo en el nativo, así que nulo es inofensivo.
  val name: String? = null
)
