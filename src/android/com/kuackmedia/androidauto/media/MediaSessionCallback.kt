package com.kuackmedia.androidauto.media

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Context.MODE_PRIVATE
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.media.session.MediaButtonReceiver
import com.kuackmedia.androidauto.CordovaEventBridge
import com.kuackmedia.androidauto.CordovaEvents
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.CURRENT_TRACK_KEY
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.QUEUE_ITEMS_KEY
import com.kuackmedia.androidauto.media.MusicLibraryService.Companion.PLAYLIST_DATA
import com.kuackmedia.androidauto.tree.MediaItemTree
import com.kuackmedia.androidauto.utils.LocalStorageUtils
import com.kuackmedia.androidauto.utils.MediaUtils
import org.json.JSONObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL


/**
 * Routes transport controls to your PlayerAdapter and
 * keeps the session’s PlaybackState in sync.
 */
class MediaSessionCallback(
  private val mediaPlayer: IPlayerAdapter,
  private val mediaSession: MediaSessionCompat,
  private val context: Context
) : MediaSessionCompat.Callback() {

  companion object {
    private const val LOAD_STALE_MS = 60000L
    private const val PLAYBACK_POSITION_UPDATE_INTERVAL: Long = 1000
    private const val TAG = "MediaSessionCallback"
    private const val NOTIFICATION_ID = 1
    private const val CHANNEL_ID = "media_playback_channel"
  }

  private val handler: Handler = Handler(Looper.getMainLooper())
  private var currentQueue: List<MediaSessionCompat.QueueItem>? = null
  private var currentTrack: MediaBrowserCompat.MediaItem? = null
  private var isCalledFromOnPrepare: Boolean = false
  private var queueLoadingState: QueueLoadingState? = null

  // Pedidos de tema (prepare de la conexión o del app, elección en el auto, saltos). Cada uno resuelve la URL en IO y
  // recién después llega al prepareAsync del player (isPreparing): en esa ventana no hay nada preparando ni preparado.
  // - loadGeneration: el resultado de un pedido viejo se descarta (el prepare de la conexión que vuelve después de que
  //   el usuario eligió otro tema ya no lo pisa).
  // - loadPending: hay un pedido abierto. Un play en la ventana sólo pide que arranque al preparar, sin otro prepare
  //   (Android Auto que se reinicia y manda play antes de que termine el prepare de la conexión).
  // Todo en el main thread. Cada camino de un pedido termina en endTrackLoad o abandonTrackLoad; si alguno quedara
  // abierto por un bug, pasados LOAD_STALE_MS (más que los timeouts de OkHttp) ya no se le cree: un timestamp, no
  // un timer.
  private var loadGeneration = 0
  private var loadPending = false
  private var loadStartedAt = 0L

  // Notificación de medios (id 1). Todo en el main thread. Cada showNotification() toma un número;
  // la versión con carátula, que llega tarde desde IO, sólo se publica si sigue siendo la última y
  // si el servicio no se destruyó (release()): si no, pisaba un estado nuevo con uno viejo o
  // re-publicaba el id 1 después del cancel(1) de MusicLibraryService.onDestroy().
  private var notificationSeq = 0
  private var released = false
  private var loggedNotificationPermission = false

  // true sólo cuando una pérdida TRANSITORIA de foco (llamada, voz) pausó un tema que sonaba, o cuando un play quedó
  // con el foco diferido: habilita reproducir en el próximo AUDIOFOCUS_GAIN. Lo apagan todo comando de la sesión
  // (cancelFocusResume), una pérdida permanente, un error y release(). Sin timers: si el GAIN no llega, queda en pausa
  // hasta que el usuario haga algo. Todo en el main thread (sesión y avisos de foco, ver init).
  private var resumeOnFocusGain = false
  // Salida de medios al armar la reanudación (sólo parlante o no): el GAIN la bloquea si cambió a sólo parlante.
  private var speakerOnlyWhenArmed = false
  private var noisyReceiverRegistered = false
  // El audio se va a salir por el parlante (se desconectó el auto, un cable o un Bluetooth): nada de reanudar.
  private val noisyReceiver = object : BroadcastReceiver() {
    override fun onReceive(c: Context?, intent: Intent?) {
      if (intent != null && intent.action == android.media.AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
        handler.post {
          if (resumeOnFocusGain) Log.i(TAG, "[FOCUS] BECOMING_NOISY: se cancela la reanudación pendiente")
          disarmFocusResume()
        }
      }
    }
  }

  init {
    // This executes when a track ends playing
    mediaPlayer.setOnCompletionListener {
      handlePlaybackCompletion()
    }

    // This executes when the track is loaded into the player
    mediaPlayer.setOnPreparedListener {
      handlePrepare()
    }

    // This executes on error
    mediaPlayer.setOnErrorListener { what, extra ->
      handleError(what, extra)
    }

    // This executes when audio focus changes
    // El AudioFocusRequest no lleva Handler: no está garantizado que el aviso llegue en el main thread, y
    // handleAudioFocusChange toca el player, la sesión y la notificación.
    mediaPlayer.setOnAudioFocusChangeListener { focusChange ->
      if (Looper.myLooper() == Looper.getMainLooper()) {
        handleAudioFocusChange(focusChange)
      } else {
        handler.post { handleAudioFocusChange(focusChange) }
      }
    }
  }

  override fun onPrepare() {
    // Check PLAYLIST_DATA to determine if current session is podcast or music
    val playlistDataRaw = CurrentMedia.readFileContent(context, PLAYLIST_DATA)
    var isPodcastSession = false
    if (playlistDataRaw != null) {
      try {
        val playlistDataJson = JSONObject(playlistDataRaw)
        isPodcastSession = playlistDataJson.optString("type") == "PODCAST"
      } catch (e: Exception) {
        Log.w(TAG, "[ON_PREPARE] Failed to parse PLAYLIST_DATA: ${e.message}")
      }
    }

    if (isPodcastSession) {
      Log.i(TAG, "[ON_PREPARE] sesión de podcast autoplay=${mediaPlayer.shouldAutoPlayOnPrepare} " +
        "preparing=${mediaPlayer.isPreparing()} prepared=${mediaPlayer.isPrepared} pending=$loadPending")
      // Podcast session: read current_episode file and play it
      val episodeRaw = CurrentMedia.readFileContent(context, "current_episode")
      if (episodeRaw != null) {
        try {
          val episodeJson = JSONObject(episodeRaw)
          val episodeId = episodeJson.optString("id", "")
          val enclosureUrl = episodeJson.optJSONObject("enclosure")?.optString("url")
          val episodeTitle = episodeJson.optString("title", "Episode")
          val showTitle = episodeJson.optString("showTitle", "Podcast")
          val imageUrl = episodeJson.optString("image", "")
          val showId = episodeJson.optString("showId", "")
          val durationMs = episodeJson.optLong("durationMs", 0L)
          val duration = episodeJson.optString("duration", "0")

          val extras = Bundle().apply {
            putString("id", episodeId)
            putString("title", episodeTitle)
            putString("artist", showTitle)
            putString("album", showTitle)
            putString("image", imageUrl)
            putString("showId", showId)
            putString("enclosure_url", enclosureUrl ?: "")
            putString("isPodcast", "true")
            putLong("durationMs", durationMs)
            putString("length", duration)
            putString("media_type", "podcast_episode")
            putString("parentData", playlistDataRaw)
          }

          val mediaId = "item_podcast_episode_$episodeId"
          isCalledFromOnPrepare = true
          this.onPlayFromMediaId(mediaId, extras)
        } catch (e: Exception) {
          Log.e(TAG, "[ON_PREPARE_PODCAST_ERROR] Failed to parse current_episode: ${e.message}", e)
          if (mediaPlayer.shouldAutoPlayOnPrepare) endWithoutMedia()
        }
      } else {
        Log.i(TAG, "[ON_PREPARE] sesión de podcast sin current_episode: no se prepara nada")
        if (mediaPlayer.shouldAutoPlayOnPrepare) endWithoutMedia()
      }
    } else {
      // Music session: standard queue-based prepare
      val prefs = this.context.getSharedPreferences("NativeStorage", MODE_PRIVATE)
      val queueReadAt = SystemClock.elapsedRealtime()
      this.currentQueue = QueueManager.getCurrentQueue(this.context)
      val queueReadMs = SystemClock.elapsedRealtime() - queueReadAt

      if(currentQueue === null) {
        Log.i(TAG, "[ON_PREPARE] sin cola guardada ($queueReadMs ms): no se prepara nada")
        if (mediaPlayer.shouldAutoPlayOnPrepare) endWithoutMedia()
      } else {
        val savedTrackId = prefs.getString(CURRENT_TRACK_KEY, null).toString().replace("\"", "")

        this.currentTrack =
          CurrentMedia.getCurrentTrackFromQueue(
            savedTrackId,
            this.currentQueue
          )
        // La lectura de la cola corre en el main thread (Moshi): el tiempo queda en el log para medirlo en gama baja.
        Log.i(TAG, "[ON_PREPARE] cola=${currentQueue?.size} guardado=$savedTrackId " +
          "encontrado=${currentTrack != null} ($queueReadMs ms) autoplay=${mediaPlayer.shouldAutoPlayOnPrepare} " +
          "preparing=${mediaPlayer.isPreparing()} prepared=${mediaPlayer.isPrepared} pending=$loadPending")

        if (currentTrack == null) {
          // El tema guardado no está en la cola (p. ej. después de reinstalar). Antes se seguía con mediaId null: la
          // URL salía null, quedaba BUFFERING con la notificación en "reproduciendo", se guardaba current_track="null"
          // y currentTrackFromApp quedaba en true, así que el primer tema elegido en el auto no arrancaba.
          if (mediaPlayer.shouldAutoPlayOnPrepare) endWithoutMedia()
          return
        }

        // When onPrepare is called (e.g., when Android Auto connects), we set a flag to prevent auto-play
        // This is not an explicit user action, so the track should be loaded but not played automatically
        isCalledFromOnPrepare = true

        // Enrich extras with parentData from playlist_data so the handler can build the queue title
        val enrichedExtras = Bundle(this.currentTrack?.description?.extras ?: Bundle())
        if (playlistDataRaw != null && enrichedExtras.getString("parentData").isNullOrEmpty()) {
          // Pass the original playlist_data directly as parentData — don't normalize.
          // This preserves the full structure (e.g. trackData for TRACK_RADIO)
          // and the original id type (number vs string) that the JS app wrote.
          enrichedExtras.putString("parentData", playlistDataRaw)
        }

        this.onPlayFromMediaId(this.currentTrack?.mediaId, enrichedExtras)
      }
    }
  }

  override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
    val mediaSessionContext = extras?.getString("MEDIA_SESSION_SERVICE_CONTEXT")
    val fromPrepare = isCalledFromOnPrepare

    // Check if this call is from onPrepare()
    if (isCalledFromOnPrepare) {
      isCalledFromOnPrepare = false  // Reset flag immediately

      // Check if shouldAutoPlayOnPrepare was already set (e.g., by playCurrentTrack from app)
      if (mediaPlayer.shouldAutoPlayOnPrepare) {
        // Keep shouldAutoPlayOnPrepare = true, it was set by playCurrentTrack()
      } else {
        // This is just Android Auto connecting, not an explicit play request
        mediaPlayer.currentTrackFromApp = true  // Mark to prevent auto-play in handlePrepare
      }
    } else {
      // Un tema elegido en el auto: siempre arranca. Los saltos no pasan por acá (van por playQueueItem).
      // Antes el flag del prepare de la conexión (currentTrackFromApp) frenaba el autoplay: si ese prepare no llegaba a
      // handlePrepare (el tema guardado no estaba en la cola, sin URL), el primer tema elegido quedaba en STOPPED.
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true
    }

    fun getDurationStringLength(length: String?, filePath: String?): Long = getDuration(length, filePath)

    if (mediaSessionContext == "MEDIA_AUTOPLAY") {
      // Optionally reset state or ignore
      return
    }

    // Desde acá el pedido reemplaza a cualquier otro abierto: el que vuelva después se descarta.
    val gen = beginTrackLoad(if (fromPrepare) "prepare" else "elegido en el auto: $mediaId")

    // Otro tema (elegido en el auto, play_all/shuffle, prepare de la conexión, playCurrentTrack del app).
    cancelFocusResume()

    // Handle play_all: and shuffle: action items from album/playlist drill-down
    if (mediaId != null && (mediaId.startsWith("play_all:") || mediaId.startsWith("shuffle:"))) {
      val shouldShuffle = mediaId.startsWith("shuffle:")
      val parts = mediaId.split(":")
      // Format: play_all:type:id or shuffle:type:id
      if (parts.size >= 3) {
        val actionMediaType = parts[1]
        val actionItemId = parts[2]

        val parentItem = MediaItemTree.getItem("item_${actionMediaType}_${actionItemId}")
        val parentName = parentItem?.description?.title?.toString() ?: ""
        val queueTitle = QueueManager.buildQueueTitle(actionMediaType, parentName)
        val parentData = JSONObject().apply {
          put("type", actionMediaType.uppercase())
          put("id", actionItemId)
          put("name", parentName)
        }.toString()

        if (shouldShuffle) {
          // Shuffle: load ALL tracks, shuffle, then play. No incremental loading.
          CoroutineScope(Dispatchers.IO).launch {
            try {
              val browsableMediaId = "item_${actionMediaType}_${actionItemId}"
              val allItems = MediaItemTree.getRemoteChildren(browsableMediaId, context)
              val tracks = allItems.filter { item ->
                val mid = item.mediaId ?: ""
                !mid.startsWith("play_all:") && !mid.startsWith("shuffle:")
              }.shuffled()

              withContext(Dispatchers.Main) {
                val loadingState = QueueLoadingState(
                  contentType = actionMediaType.uppercase(),
                  contentId = actionItemId,
                  contentName = parentName,
                  parentData = parentData,
                  currentOffset = tracks.size,
                  hasMore = false
                )
                startPlaybackWithInitialTracks(tracks, queueTitle, loadingState, gen)
              }
            } catch (e: Exception) {
              Log.e(TAG, "[ACTION_SHUFFLE] Error: ${e.message}", e)
              abandonTrackLoad(gen)
            }
          }
        } else {
          // Play all: load 2 tracks, play immediately, then load more incrementally
          CoroutineScope(Dispatchers.IO).launch {
            try {
              val initialTracks = when (actionMediaType.uppercase()) {
                "ALBUM" -> MediaItemTree.getAlbumTracksPage(actionItemId, parentData, context, limit = 2, offset = 0)
                "PLAYLIST" -> MediaItemTree.getPlaylistTracksPage(actionItemId, parentData, context, limit = 2, offset = 0)
                "ARTIST" -> MediaItemTree.getArtistTracksPage(actionItemId, parentData, context, limit = 2, offset = 0)
                else -> MediaItemTree.getAlbumTracksPage(actionItemId, parentData, context, limit = 2, offset = 0)
              }

              withContext(Dispatchers.Main) {
                val loadingState = QueueLoadingState(
                  contentType = actionMediaType.uppercase(),
                  contentId = actionItemId,
                  contentName = parentName,
                  parentData = parentData,
                  currentOffset = initialTracks.size
                )
                startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
              }
            } catch (e: Exception) {
              Log.e(TAG, "[ACTION_PLAY_ALL] Error: ${e.message}", e)
              abandonTrackLoad(gen)
            }
          }
        }
        return
      }
    }

    // Extraer mediaType del mediaId si extras es nulo
    var mediaType: String? = extras?.getString("media_type")
    if (mediaType == null && mediaId != null) {
      // Espera formato: item_type_id
      val parts = mediaId.split("_")
      if (parts.size >= 3) {
        mediaType = parts[1]
      }
    }

    // autoplay artist: load 2 tracks, play immediately, then load more
    if (mediaType == "artist" && mediaId != null) {
      val artistItem = MediaItemTree.getItem(mediaId)
      val artistName = artistItem?.description?.title?.toString() ?: ""
      val artistId = mediaId.removePrefix("item_artist_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }
      val parentData = JSONObject().apply {
        put("type", "ARTIST")
        put("id", artistId)
        put("name", artistName)
      }.toString()
      val queueTitle = QueueManager.buildQueueTitle("ARTIST", artistName)

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val initialTracks = MediaItemTree.getArtistTracksPage(artistId, parentData, context, limit = 2, offset = 0)
          withContext(Dispatchers.Main) {
            val loadingState = QueueLoadingState(
              contentType = "ARTIST",
              contentId = artistId,
              contentName = artistName,
              parentData = parentData,
              currentOffset = initialTracks.size
            )
            startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
          }
        } catch (e: Exception) {
          Log.e(TAG, "[ARTIST_PLAY] Error: ${e.message}", e)
          abandonTrackLoad(gen)
        }
      }
      return
    }

    // Track play: instant start with selected track + sibling buffer, then incremental loading
    if (mediaType == "track" && mediaId != null) {
      val selectedItem = MediaItemTree.getItem(mediaId)
      if (selectedItem != null) {
        val fe = selectedItem.description.extras!!
        val idAlbumTrack = fe.getString("idAlbumTrack")
        val idAlbumTrackLong = idAlbumTrack?.toLongOrNull()
        val trackId = fe.getString("id") ?: ""

        // Build initial queue: selected track + next sibling from cache as buffer
        val initialQueue = mutableListOf(selectedItem)
        val parentDataStr = fe.getString("parentData")
        var queueTitle: String? = null
        var pdType = ""
        var pdId = ""
        var pdName = ""

        if (!parentDataStr.isNullOrEmpty()) {
          try {
            val pd = JSONObject(parentDataStr)
            pdType = pd.optString("type", "")
            pdId = pd.optString("id", "")
            pdName = pd.optString("name", "")
            if (pdType.isNotEmpty() && pdName.isNotEmpty()) {
              queueTitle = QueueManager.buildQueueTitle(pdType, pdName)
            }
            // Try to get next sibling from tree cache (no API call)
            val browsableMediaId = when (pdType.uppercase()) {
              "ALBUM" -> "item_album_$pdId"
              "PLAYLIST", "MIX" -> "item_playlist_$pdId"
              "ARTIST" -> "item_artist_$pdId"
              else -> null
            }
            if (browsableMediaId != null) {
              val cachedChildren = MediaItemTree.getChildren(browsableMediaId)
              if (cachedChildren.isNotEmpty()) {
                val selectedIndex = cachedChildren.indexOfFirst { it.mediaId == mediaId }
                if (selectedIndex >= 0 && selectedIndex + 1 < cachedChildren.size) {
                  initialQueue.add(cachedChildren[selectedIndex + 1])
                }
              }
            }
          } catch (e: Exception) {
            Log.w(TAG, "[TRACK_PLAY_BUFFER] Failed to get buffer track: ${e.message}")
          }
        }
        if (queueTitle == null) {
          queueTitle = QueueManager.buildQueueTitle("TRACK_RADIO", fe.getString("title") ?: "")
        }

        // Offline: load ALL tracks at once via getRemoteChildren (handles offline internally)
        // loadMore() won't work without network, so we must load everything upfront
        val isOffline = !MusicLibraryService.isNetworkEnabled(context)
        if (isOffline && pdType.uppercase() in listOf("ALBUM", "PLAYLIST", "MIX", "ARTIST")) {
          val browsableMediaId = when (pdType.uppercase()) {
            "ALBUM" -> "item_album_$pdId"
            "PLAYLIST", "MIX" -> "item_playlist_$pdId"
            "ARTIST" -> "item_artist_$pdId"
            else -> null
          }
          if (browsableMediaId != null) {
            CoroutineScope(Dispatchers.IO).launch {
              try {
                val allItems = MediaItemTree.getRemoteChildren(browsableMediaId, context)
                val allTracks = allItems.filter { item ->
                  val mid = item.mediaId ?: ""
                  !mid.startsWith("play_all:") && !mid.startsWith("shuffle:")
                }
                if (allTracks.isNotEmpty()) {
                  val selectedIndex = allTracks.indexOfFirst { it.mediaId == mediaId }
                  val reorderedTracks = if (selectedIndex >= 0) {
                    allTracks.subList(selectedIndex, allTracks.size) + allTracks.subList(0, selectedIndex)
                  } else {
                    listOf(selectedItem) + allTracks.filter { it.mediaId != mediaId }
                  }
                  withContext(Dispatchers.Main) {
                    val offlineLoadingState = QueueLoadingState(
                      contentType = pdType.uppercase(),
                      contentId = pdId,
                      contentName = pdName,
                      parentData = parentDataStr ?: "",
                      currentOffset = reorderedTracks.size,
                      hasMore = false
                    )
                    startPlaybackWithInitialTracks(reorderedTracks, queueTitle!!, offlineLoadingState, gen)
                  }
                } else {
                  abandonTrackLoad(gen)
                }
              } catch (e: Exception) {
                Log.e(TAG, "[OFFLINE_TRACK_PLAY] Error loading offline tracks: ${e.message}", e)
                abandonTrackLoad(gen)
              }
            }
            return
          }
        }

        // Determine the QueueLoadingState based on parentData type
        // For offset-based types, we need to find the selected track's position in the container
        val loadingState: QueueLoadingState = when (pdType.uppercase()) {
          "ALBUM" -> {
            // Find selected track's offset in album: count items before it in cache
            val cachedChildren = MediaItemTree.getChildren("item_album_$pdId")
            val selectedIndex = if (cachedChildren.isNotEmpty()) {
              cachedChildren.indexOfFirst { it.mediaId == mediaId }.let { if (it < 0) 0 else it }
            } else 0
            QueueLoadingState(
              contentType = "ALBUM", contentId = pdId, contentName = pdName,
              parentData = parentDataStr ?: "",
              currentOffset = selectedIndex + initialQueue.size
            )
          }
          "PLAYLIST", "MIX" -> {
            val cachedChildren = MediaItemTree.getChildren("item_playlist_$pdId")
            val selectedIndex = if (cachedChildren.isNotEmpty()) {
              cachedChildren.indexOfFirst { it.mediaId == mediaId }.let { if (it < 0) 0 else it }
            } else 0
            QueueLoadingState(
              contentType = if (pdType.uppercase() == "MIX") "MIX" else "PLAYLIST",
              contentId = pdId, contentName = pdName,
              parentData = parentDataStr ?: "",
              currentOffset = selectedIndex + initialQueue.size
            )
          }
          "ARTIST" -> {
            val cachedChildren = MediaItemTree.getChildren("item_artist_$pdId")
            val selectedIndex = if (cachedChildren.isNotEmpty()) {
              cachedChildren.indexOfFirst { it.mediaId == mediaId }.let { if (it < 0) 0 else it }
            } else 0
            QueueLoadingState(
              contentType = "ARTIST", contentId = pdId, contentName = pdName,
              parentData = parentDataStr ?: "",
              currentOffset = selectedIndex + initialQueue.size
            )
          }
          else -> {
            // Fallback: track radio with related tracks
            val trackName = fe.getString("title") ?: ""
            val trackJsonStr = fe.getString("track") ?: "{}"
            val trackIdLong = trackId.toLongOrNull() ?: 0L
            val radioParentData = JSONObject().apply {
              put("type", "TRACK_RADIO")
              put("id", trackIdLong)
              put("trackData", JSONObject(trackJsonStr))
            }.toString()
            val seedIds = mutableListOf<Long>()
            val excludeIds = mutableListOf<Long>()
            if (idAlbumTrackLong != null) {
              seedIds.add(idAlbumTrackLong)
              excludeIds.add(idAlbumTrackLong)
            }
            // Add sibling buffer track IDs to excludes
            initialQueue.drop(1).forEach { track ->
              val iat = track.description.extras?.getString("idAlbumTrack")?.toLongOrNull()
              if (iat != null) excludeIds.add(iat)
            }
            QueueLoadingState(
              contentType = "TRACK_RADIO", contentId = trackId, contentName = trackName,
              parentData = radioParentData,
              seedAlbumTrackIds = seedIds,
              excludeAlbumTrackIds = excludeIds
            )
          }
        }

        startPlaybackWithInitialTracks(initialQueue, queueTitle!!, loadingState, gen)
        return
      }
    }

    // radio_track: play selected track + 1 related, then load more via continuation
    if (mediaType == "radio_track" && mediaId != null) {
      val selectedItem = MediaItemTree.getItem(mediaId)
      if (selectedItem != null) {
        val fe = selectedItem.description.extras!!
        val trackIdForApi = fe.getString("id") ?: mediaId.split("_").lastOrNull() ?: ""
        val trackName = fe.getString("title") ?: ""
        val idAlbumTrack = fe.getString("idAlbumTrack")
        val idAlbumTrackLong = idAlbumTrack?.toLongOrNull()

        // Build parentData with TRACK_RADIO type + full trackData for JS app sync
        val trackJson = fe.getString("track") ?: "{}"
        val trackIdLong = trackIdForApi.toLongOrNull() ?: 0L
        val radioParentData = JSONObject().apply {
          put("type", "TRACK_RADIO")
          put("id", trackIdLong)
          put("trackData", JSONObject(trackJson))
        }.toString()
        val queueTitle = QueueManager.buildQueueTitle("TRACK_RADIO", trackName)

        CoroutineScope(Dispatchers.IO).launch {
          try {
            // Load 1 related track as buffer (selected track + 1 related = 2 initial)
            val relatedTracks = MediaItemTree.getRelatedTracksPage(trackIdForApi, radioParentData, context, limit = 1)
            val initialTracks = mutableListOf(selectedItem)
            initialTracks.addAll(relatedTracks)

            // Collect seed and exclude IDs for continuation
            val seedIds = mutableListOf<Long>()
            val excludeIds = mutableListOf<Long>()
            if (idAlbumTrackLong != null) {
              seedIds.add(idAlbumTrackLong)
              excludeIds.add(idAlbumTrackLong)
            }
            relatedTracks.forEach { track ->
              val iat = track.description.extras?.getString("idAlbumTrack")?.toLongOrNull()
              if (iat != null) excludeIds.add(iat)
            }

            // Override parentData on all tracks for correct storeLocalData
            initialTracks.forEach { track ->
              track.description.extras?.putString("parentData", radioParentData)
            }

            withContext(Dispatchers.Main) {
              val loadingState = QueueLoadingState(
                contentType = "TRACK_RADIO",
                contentId = trackIdForApi,
                contentName = trackName,
                parentData = radioParentData,
                seedAlbumTrackIds = seedIds,
                excludeAlbumTrackIds = excludeIds
              )
              startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
            }
          } catch (e: Exception) {
            Log.e(TAG, "[RADIO_TRACK_ERROR] Exception: ${e.message}", e)
            abandonTrackLoad(gen)
          }
        }
        return
      }
    }

    // radio (tag_radio): load 2 tracks, play immediately, then load more with cursor
    if (mediaType == "radio" && mediaId != null) {
      val stationId = mediaId.removePrefix("item_radio_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }

      val parentItem = MediaItemTree.getItem(mediaId)
      val itemName = parentItem?.description?.title?.toString() ?: ""
      val parentData = JSONObject().apply {
        put("type", "RADIO")
        put("id", stationId)
        put("name", itemName)
      }.toString()
      val queueTitle = QueueManager.buildQueueTitle("RADIO", itemName)

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val initialTracks = MediaItemTree.getStationRadioPage(stationId, parentData, context, count = 2)
          if (initialTracks.isNotEmpty()) {
            // Get lastIdAlbumTrack for cursor-based pagination
            val lastIAT = initialTracks.last().description.extras
              ?.getString("idAlbumTrack")?.toLongOrNull()

            withContext(Dispatchers.Main) {
              val loadingState = QueueLoadingState(
                contentType = "RADIO",
                contentId = stationId,
                contentName = itemName,
                parentData = parentData,
                lastIdAlbumTrack = lastIAT
              )
              startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
            }
          } else {
            abandonTrackLoad(gen)
          }
        } catch (e: Exception) {
          Log.e(TAG, "[TAG_RADIO_ERROR] Exception: ${e.message}", e)
          abandonTrackLoad(gen)
        }
      }
      return
    }

    // artist_radio: load 2 tracks by popularity (no shuffle), then load more
    if (mediaType == "artist_radio" && mediaId != null) {
      val artistId = mediaId.removePrefix("item_artist_radio_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }

      val parentItem = MediaItemTree.getItem(mediaId)
      val itemName = parentItem?.description?.title?.toString() ?: ""
      val parentData = JSONObject().apply {
        put("type", "ARTIST_STATION")
        put("id", artistId)
        put("name", itemName)
      }.toString()
      val queueTitle = QueueManager.buildQueueTitle("ARTIST_STATION", itemName)

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val initialTracks = MediaItemTree.getArtistTracksPage(
            artistId, parentData, context, limit = 2, offset = 0, order = "popularity"
          )
          if (initialTracks.isNotEmpty()) {
            withContext(Dispatchers.Main) {
              val loadingState = QueueLoadingState(
                contentType = "ARTIST_STATION",
                contentId = artistId,
                contentName = itemName,
                parentData = parentData,
                currentOffset = initialTracks.size
              )
              startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
            }
          } else {
            abandonTrackLoad(gen)
          }
        } catch (e: Exception) {
          Log.e(TAG, "[ARTIST_RADIO_ERROR] Exception: ${e.message}", e)
          abandonTrackLoad(gen)
        }
      }
      return
    }

    if (mediaType == "album" && mediaId != null) {
      val albumItem = MediaItemTree.getItem(mediaId)
      val albumName = albumItem?.description?.title?.toString() ?: ""
      val albumId = mediaId.removePrefix("item_album_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }
      val parentData = JSONObject().apply {
        put("type", "ALBUM")
        put("id", albumId)
        put("name", albumName)
      }.toString()
      val queueTitle = QueueManager.buildQueueTitle("ALBUM", albumName)

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val initialTracks = MediaItemTree.getAlbumTracksPage(albumId, parentData, context, limit = 2, offset = 0)
          withContext(Dispatchers.Main) {
            val loadingState = QueueLoadingState(
              contentType = "ALBUM",
              contentId = albumId,
              contentName = albumName,
              parentData = parentData,
              currentOffset = initialTracks.size
            )
            startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
          }
        } catch (e: Exception) {
          Log.e(TAG, "[ALBUM_PLAY] Error: ${e.message}", e)
          abandonTrackLoad(gen)
        }
      }
      return
    }

    // autoplay playlist: load 2 tracks, play immediately, then load more
    if (mediaType == "playlist" && mediaId != null) {
      val playlistItem = MediaItemTree.getItem(mediaId)
      val playlistName = playlistItem?.description?.title?.toString() ?: ""
      val playlistId = mediaId.removePrefix("item_playlist_")
        .let { if (it.endsWith(".0")) it.dropLast(2) else it }
      val parentData = JSONObject().apply {
        put("type", "PLAYLIST")
        put("id", playlistId)
        put("name", playlistName)
      }.toString()
      val queueTitle = QueueManager.buildQueueTitle("PLAYLIST", playlistName)

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val initialTracks = MediaItemTree.getPlaylistTracksPage(playlistId, parentData, context, limit = 2, offset = 0)
          withContext(Dispatchers.Main) {
            val loadingState = QueueLoadingState(
              contentType = "PLAYLIST",
              contentId = playlistId,
              contentName = playlistName,
              parentData = parentData,
              currentOffset = initialTracks.size
            )
            startPlaybackWithInitialTracks(initialTracks, queueTitle, loadingState, gen)
          }
        } catch (e: Exception) {
          Log.e(TAG, "[PLAYLIST_PLAY] Error: ${e.message}", e)
          abandonTrackLoad(gen)
        }
      }
      return
    }

    // Podcast episode: resolve audio from offline file or enclosure URL
    if ((mediaType == "podcast_episode" || mediaType == "podcastEpisode") && mediaId != null) {
      val episodeId = extras?.getString("id") ?: mediaId.removePrefix("item_podcast_episode_").removePrefix("item_podcastEpisode_")
      val enclosureUrl = extras?.getString("enclosure_url")
      val showId = extras?.getString("showId") ?: ""
      val episodeTitle = extras?.getString("title") ?: "Episode"
      val showTitle = extras?.getString("artist") ?: "Podcast"
      val imageUrl = extras?.getString("image") ?: ""

      val episodeUri = LocalStorageUtils.getEpisodeUri(context, episodeId, enclosureUrl)
      endTrackLoad(gen, episodeUri)
      if (episodeUri != null) {
        // Build a single-episode queue (podcast episodes play individually)
        val selectedItem = MediaItemTree.getItem(mediaId)
        if (selectedItem != null) {
          QueueManager.buildQueue(listOf(selectedItem))
        }

        mediaPlayer.setCurrentTrack(episodeUri)
        mediaPlayer.playCurrentTrack(context)
        updateState(PlaybackStateCompat.STATE_BUFFERING, 0)

        // Duration: prefer durationMs from extras, fallback to parsing duration string
        val durationMs = extras?.getLong("durationMs", 0L) ?: 0L
        val duration = if (durationMs > 0) durationMs else getDurationStringLength(extras?.getString("length", "0"), episodeUri.toString())

        mediaSession.setMetadata(
          MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, episodeTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, showTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, showTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, imageUrl)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
            .build()
        )
        showNotification(PlaybackStateCompat.STATE_PLAYING)

        // Store parentData for JS app sync
        val podcastParentData = JSONObject().apply {
          put("type", "PODCAST")
          put("id", showId)
          put("name", showTitle)
        }.toString()
        val podcastExtras = Bundle(extras ?: Bundle())
        podcastExtras.putString("parentData", podcastParentData)
        storePodcastLocalData(podcastExtras, episodeId)

        QueueManager.setQueue(mediaSession, QueueManager.buildQueueTitle("PODCAST", showTitle))
      } else {
        Log.e(TAG, "[PODCAST_EPISODE_PLAY_ERROR] Could not resolve episode URI for episodeId=$episodeId")
        if (mediaPlayer.shouldAutoPlayOnPrepare) endWithoutMedia()
        else {
          mediaPlayer.currentTrackFromApp = false
        }
      }
      return
    }

    // Siempre se lanza, también con otro tema en prepareAsync: playCurrentTrack resetea el player y la generación
    // descarta lo viejo. Antes el pedido se ignoraba y, con los flags del pedido nuevo, sonaba el tema anterior.
    run {
      val trackId = extras?.getString("idAlbumTrack")

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val trackUrl: Uri? = LocalStorageUtils.getTrackUri(context, extras?.getString("id"),
            trackId)
          withContext(Dispatchers.Main) {
            if (!isCurrentLoad(gen, "onPlayFromMediaId")) return@withContext
            endTrackLoad(gen, trackUrl)
            // Build queue title from parentData if available
            val parentDataStr = extras?.getString("parentData")
            var queueTitle: String? = null
            if (!parentDataStr.isNullOrEmpty()) {
              try {
                val pd = JSONObject(parentDataStr)
                val pdType = pd.optString("type", "")
                var pdName = pd.optString("name", "")
                // TRACK_RADIO stores name inside trackData, not at top level
                if (pdName.isEmpty() && pdType.equals("TRACK_RADIO", ignoreCase = true)) {
                  pdName = pd.optJSONObject("trackData")?.optString("name", "") ?: ""
                }
                if (pdType.isNotEmpty() && pdName.isNotEmpty()) {
                  queueTitle = QueueManager.buildQueueTitle(pdType, pdName)
                }
              } catch (e: Exception) {
                Log.w(TAG, "[onPlayFromMediaId] Failed to parse parentData for queue title: ${e.message}")
              }
            }
            QueueManager.setQueue(mediaSession, queueTitle)
            mediaPlayer.setCurrentTrack(trackUrl)
            mediaPlayer.playCurrentTrack(context)

            if (trackUrl != null) updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
            var durationText = extras?.getString("length", "0");
           val durationMs = getDurationStringLength(durationText, trackUrl.toString())
            val metadata = MediaMetadataCompat.Builder()
              .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras?.getString("title"))
              .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras?.getString("artist"))
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras?.getString("album"))
              .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, extras?.getString("image"))
              .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
              .build()

            mediaSession.setMetadata(metadata)

            // Sin URL: en pausa, pero la cola y current_track se guardan igual (como antes), así el app ve lo mismo
            // que el auto.
            if (trackUrl == null) endWithoutMedia() else showNotification(PlaybackStateCompat.STATE_PLAYING)

            //storeLocalData(extras, trackId)
            extras?.let { storeLocalData(it, trackId) }
          }
        } catch (e: Exception) {
          Log.e("MediaSession", "Failed to load track URI", e)
          abandonTrackLoad(gen)
        }
      }
    }
  }

  override fun onPlay() {
    cancelFocusResume()
    // Hay un tema cargando (la URL en IO o el prepareAsync): el play sólo pide que arranque al terminar, sin un segundo
    // prepare. Pasa cuando Android Auto se reinicia y manda play antes de que termine el prepare de la conexión: antes
    // el play fallaba sin foco y el prepare terminaba en STOPPED.
    val preparing = mediaPlayer.isPreparing()
    val pending = loadPending && SystemClock.elapsedRealtime() - loadStartedAt < LOAD_STALE_MS
    if (preparing || pending) {
      mediaPlayer.shouldAutoPlayOnPrepare = true
      mediaPlayer.currentTrackFromApp = false
      Log.i(TAG, "[ON_PLAY] tema cargando (pedido $loadGeneration, preparing=$preparing): arranca al terminar")
      // Que el auto muestre que tomó el play (si no, sigue en Play y el usuario vuelve a tocar).
      if (!mediaPlayer.isPlaying()) updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
      return
    }
    if (loadPending) {
      // Vencido: si el resultado llega igual, se descarta (otra generación) en lugar de aplicarse con flags ajenos.
      Log.w(TAG, "[ON_PLAY] el pedido $loadGeneration lleva más de ${LOAD_STALE_MS / 1000} s abierto: se descarta")
      loadGeneration++
      loadPending = false
      mediaPlayer.shouldAutoPlayOnPrepare = false
    }
    // Nada preparado ni cargando (un tema que quedó sin URL, un error, un stop): play() llamaría start() sobre un
    // player sin preparar (error -38) o reanudaría el tema anterior con la metadata del nuevo. Con el auto conectado se
    // vuelve a pedir el tema actual de la cola (reintento, por ejemplo cuando volvió la red); sin auto, sólo el aviso.
    if (!mediaPlayer.isPlaying() && !mediaPlayer.isPrepared) {
      // El tema que muestra el auto (la metadata), buscado en la cola de la sesión: el índice de QueueManager no siempre
      // es el suyo (la rama genérica no lo sincroniza). Un episodio no se reintenta por acá: su URL no sale de
      // getTrackUri.
      val shownId = mediaSession.controller.metadata?.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID)
      val shown = if (shownId == null) null
        else mediaSession.controller.queue?.firstOrNull { it.description.mediaId == shownId }
      val shownExtras = shown?.description?.extras
      val shownIsEpisode = shownExtras != null && (shownExtras.getString("isPodcast") == "true" ||
        shownExtras.getString("media_type") == "podcast_episode" || shownExtras.getString("media_type") == "podcastEpisode")
      val item = if (shown != null && !shownIsEpisode) QueueManager.getItem(mediaSession, shown.queueId) else null
      if (item != null && MediaControlBridge.androidAutoConnected) {
        Log.i(TAG, "[ON_PLAY] nada preparado: se vuelve a pedir el tema actual de la cola (${item.description.mediaId})")
        mediaPlayer.currentTrackFromApp = false
        mediaPlayer.shouldAutoPlayOnPrepare = true
        playQueueItem(item)
      } else {
        Log.w(TAG, "[ON_PLAY] nada preparado y sin tema para pedir (auto=${MediaControlBridge.androidAutoConnected})")
        endWithoutMedia()
      }
      return
    }
    if(!mediaPlayer.isPreparing()) {
      // If the player is already playing, just update state and return
      if (mediaPlayer.isPlaying()) {
        updateState(PlaybackStateCompat.STATE_PLAYING)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        CordovaEventBridge.sendEvent(
          CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
          JSONObject().put("action", "play"))
        return
      }

      // Request audio focus before starting playback
      val hasFocus = mediaPlayer.requestAudioFocusForPlayback()

      if (hasFocus) {
        mediaPlayer.play()
        updateState(PlaybackStateCompat.STATE_PLAYING)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        CordovaEventBridge.sendEvent(
          CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
          JSONObject().put("action", "play"))
      } else {
        Log.w(TAG, "[ON_PLAY_NO_FOCUS] Could not gain audio focus, playback not started")
        updateState(PlaybackStateCompat.STATE_PAUSED)
        // Sin este aviso el JS quedaba esperando un 'play' que no llega. Con el foco diferido (una llamada en curso),
        // el usuario quiere que suene: arranca cuando llegue el GAIN.
        emitPrepareWithoutFocus()
      }
    }
  }

  override fun onStop() {
    cancelFocusResume()
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.stop()
      updateState(PlaybackStateCompat.STATE_STOPPED, 0)
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      showNotification(PlaybackStateCompat.STATE_STOPPED)
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "stop"))
    }
  }

  override fun onPause() {
    // Antes de la ventana de 500 ms: una pausa del usuario cancela la reanudación aunque después se descarte.
    cancelFocusResume()
    // Check if we should ignore pause commands during audio focus stabilization period
    if (mediaPlayer.shouldIgnorePauseCommands()) {
      return
    }

    if(!mediaPlayer.isPreparing()) {
      // La posición antes de pausar: con el player en pausa el adapter devuelve 0 y el auto mostraba 0:00.
      val position = mediaPlayer.currentPosition
      mediaPlayer.pause()
      updateState(PlaybackStateCompat.STATE_PAUSED, position)
      showNotification(PlaybackStateCompat.STATE_PAUSED)
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "pause"))
    }
  }

  override fun onSkipToNext() {
    cancelFocusResume()
    if(!mediaPlayer.isPreparing()) {
      // Reset flags and enable auto-play for the next track
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true

      val nextItem = QueueManager.getNextQueueItem(mediaSession)
      if (nextItem != null) {
        playQueueItem(nextItem)
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToNext"))
    }
  }

  override fun onSkipToPrevious() {
    cancelFocusResume()
    if(!mediaPlayer.isPreparing()) {
      // Reset flags and enable auto-play for the previous track
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true

      val previousItem = QueueManager.getPreviousQueueItem(mediaSession)
      if (previousItem != null) {
        playQueueItem(previousItem)
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToPrevious"))
    }
  }

  override fun onSeekTo(pos: Long) {
    cancelFocusResume()
    if(!mediaPlayer.isPreparing()) {
      mediaPlayer.seekTo(pos)

      updateState(
        if (mediaPlayer.isPlaying()) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
        pos
      )

      if (mediaPlayer.isPlaying()) {
        handler.removeCallbacks(updatePlaybackPositionRunnable)
        handler.post(updatePlaybackPositionRunnable)
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "seekTo").put("value", pos))
    }
  }

  override fun onSkipToQueueItem(id: Long) {
    cancelFocusResume()
    if(!mediaPlayer.isPreparing()) {
      // Reset flags and enable auto-play for the selected track
      mediaPlayer.currentTrackFromApp = false
      mediaPlayer.shouldAutoPlayOnPrepare = true

      val nextItem = QueueManager.getItem(mediaSession, id)
      if(nextItem != null) {
        playQueueItem(nextItem)
      }
      CordovaEventBridge.sendEvent(
        CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
        JSONObject().put("action", "skipToQueueItem"))
    }
  }

  /**
   * Common helper: plays the first track from initialTracks, sets up metadata,
   * stores local data, and triggers the first async batch via loadMore().
   */
  private fun startPlaybackWithInitialTracks(
    initialTracks: List<MediaBrowserCompat.MediaItem>,
    queueTitle: String,
    loadingState: QueueLoadingState,
    gen: Int
  ) {
    // Antes de tocar la cola: la lista llegó por red y el usuario pudo haber elegido otra cosa mientras tanto.
    if (!isCurrentLoad(gen, "startPlayback")) return
    if (initialTracks.isEmpty()) {
      Log.w(TAG, "[START_PLAYBACK] No initial tracks to play")
      endTrackLoad(gen, null)
      if (mediaPlayer.shouldAutoPlayOnPrepare) endWithoutMedia() else mediaPlayer.currentTrackFromApp = false
      return
    }

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val first = initialTracks.first()
        val fe = first.description.extras!!
        val idAlbumTrack = fe.getString("idAlbumTrack")
        val uri = LocalStorageUtils.getTrackUri(context, fe.getString("id"), idAlbumTrack)

        withContext(Dispatchers.Main) {
          if (!isCurrentLoad(gen, "startPlayback/url")) return@withContext
          endTrackLoad(gen, uri)
          // Recién acá, con el pedido vigente: uno descartado no deja la cola interna ni el estado de paginado.
          this@MediaSessionCallback.queueLoadingState = loadingState
          QueueManager.buildQueue(initialTracks)
          QueueManager.setQueue(mediaSession, queueTitle)
          mediaPlayer.setCurrentTrack(uri)
          mediaPlayer.playCurrentTrack(context)
          if (uri != null) updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
          val duration = getDuration(fe.getString("length"), uri.toString())

          mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
              .putString(MediaMetadataCompat.METADATA_KEY_TITLE, fe.getString("title"))
              .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, fe.getString("artist"))
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, fe.getString("album"))
              .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, first.description.mediaId)
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, fe.getString("image"))
              .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
              .build()
          )
          if (uri == null) endWithoutMedia() else showNotification(PlaybackStateCompat.STATE_PLAYING)
          storeLocalData(fe, idAlbumTrack)
          loadMore()

          // Start preloading next tracks
          TrackPreloader.preloadNextTracks(context, mediaSession)
        }
      } catch (e: Exception) {
        Log.e(TAG, "[START_PLAYBACK] Error: ${e.message}", e)
        abandonTrackLoad(gen)
      }
    }
  }

  /**
   * Loads the next batch of 15 tracks based on queueLoadingState.
   * Called after initial playback and when approaching end of queue.
   */
  private fun loadMore() {
    val state = queueLoadingState ?: return
    if (!state.hasMore || state.isLoading) {
      return
    }

    state.isLoading = true

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val newTracks: List<MediaBrowserCompat.MediaItem> = when (state.contentType) {
          "ALBUM" -> {
            MediaItemTree.getAlbumTracksPage(
              state.contentId, state.parentData, context,
              limit = 15, offset = state.currentOffset
            )
          }
          "PLAYLIST", "MIX" -> {
            MediaItemTree.getPlaylistTracksPage(
              state.contentId, state.parentData, context,
              limit = 15, offset = state.currentOffset
            )
          }
          "ARTIST" -> {
            MediaItemTree.getArtistTracksPage(
              state.contentId, state.parentData, context,
              limit = 15, offset = state.currentOffset
            )
          }
          "ARTIST_STATION" -> {
            MediaItemTree.getArtistTracksPage(
              state.contentId, state.parentData, context,
              limit = 15, offset = state.currentOffset, order = "popularity"
            )
          }
          "RADIO" -> {
            MediaItemTree.getStationRadioPage(
              state.contentId, state.parentData, context,
              count = 15, lastIdAlbumTrack = state.lastIdAlbumTrack
            )
          }
          "TRACK_RADIO" -> {
            val currentQueue = mediaSession.controller.queue ?: emptyList()
            val allAlbumTrackIds = currentQueue.mapNotNull {
              it.description.extras?.getString("idAlbumTrack")?.toLongOrNull()
            }
            MediaItemTree.getTrackRadioContinuation(
              albumTrackIds = allAlbumTrackIds.takeLast(5),
              excludeAlbumTrackIds = state.excludeAlbumTrackIds,
              seedAlbumTrackIds = state.seedAlbumTrackIds,
              parentData = state.parentData, context = context, limit = 15
            )
          }
          else -> {
            Log.w(TAG, "[LOAD_MORE] Unknown contentType: ${state.contentType}")
            emptyList()
          }
        }

        if (newTracks.isEmpty()) {
          state.hasMore = false
        } else {
          when (state.contentType) {
            "RADIO" -> {
              val lastIAT = newTracks.last().description.extras
                ?.getString("idAlbumTrack")?.toLongOrNull()
              state.lastIdAlbumTrack = lastIAT
            }
            "TRACK_RADIO" -> {
              newTracks.forEach { track ->
                val iat = track.description.extras
                  ?.getString("idAlbumTrack")?.toLongOrNull()
                if (iat != null) state.excludeAlbumTrackIds.add(iat)
              }
            }
            else -> {
              state.currentOffset += newTracks.size
            }
          }

          withContext(Dispatchers.Main) {
            // Mientras cargaba, el usuario pudo haber elegido otra cosa (otro estado de paginado) o el servicio se
            // liberó: la página ya no corresponde a la cola de la sesión.
            if (released || state !== queueLoadingState) {
              Log.i(TAG, "[LOAD_MORE] página descartada: la cola cambió mientras cargaba")
              return@withContext
            }
            val appended = QueueManager.appendQueue(newTracks, mediaSession)
            val currentMediaId = mediaSession.controller.metadata
              ?.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID)
            val currentQueueItem = mediaSession.controller.queue?.find {
              it.description.mediaId == currentMediaId
            }
            currentQueueItem?.description?.extras?.let { extras ->
              storeLocalData(extras, extras.getString("idAlbumTrack"))
            }
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "[LOAD_MORE] Error: ${e.message}", e)
      } finally {
        state.isLoading = false
      }
    }
  }

  private fun getDuration(length: String?, filePath: String?): Long {
    var duration: Long = 0
    if (!length.isNullOrEmpty()) {
      duration = MediaUtils.parseDuration(length)
    } else {
      if (!filePath.isNullOrEmpty()) duration = MediaUtils.getMp3Duration(filePath)
      else duration = 0
    }
    return duration
  }

  private fun playQueueItem(queueItem: MediaSessionCompat.QueueItem) {
    val extras = queueItem.description.extras
    if (extras == null) {
      Log.e(TAG, "[PLAY_QUEUE_ITEM] extras is null for ${queueItem.description.mediaId}")
      return
    }
    val idAlbumTrack = extras.getString("idAlbumTrack")
    val gen = beginTrackLoad("cola: ${queueItem.description.mediaId}")

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val uri = LocalStorageUtils.getTrackUri(context, extras.getString("id"), idAlbumTrack)
        withContext(Dispatchers.Main) {
          if (!isCurrentLoad(gen, "playQueueItem")) return@withContext
          endTrackLoad(gen, uri)
          mediaPlayer.setCurrentTrack(uri)
          mediaPlayer.playCurrentTrack(context)
          if (uri != null) updateState(PlaybackStateCompat.STATE_BUFFERING, 0)
          val duration = getDuration(extras.getString("length"), uri.toString())

          mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
              .putString(MediaMetadataCompat.METADATA_KEY_TITLE, extras.getString("title"))
              .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, extras.getString("artist"))
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, extras.getString("album"))
              .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, queueItem.description.mediaId)
              .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, extras.getString("image"))
              .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
              .build()
          )
          if (uri == null) endWithoutMedia() else showNotification(PlaybackStateCompat.STATE_PLAYING)
          storeLocalData(extras, idAlbumTrack)

          // Check if we need to load more tracks
          if (QueueManager.shouldLoadMore(3)) {
            loadMore()
          }

          // Preload next tracks for offline availability
          TrackPreloader.preloadNextTracks(context, mediaSession)
        }
      } catch (e: Exception) {
        Log.e(TAG, "[PLAY_QUEUE_ITEM] Error: ${e.message}", e)
        abandonTrackLoad(gen)
      }
    }
  }

  /**
   * Stores podcast episode data in files that the JS app reads for podcast playback sync.
   * Unlike storeLocalData() which writes music queue keys, this writes:
   * - current_episode: episode JSON (read by Queue.js intFromStorage via FileSystemJSONStorage)
   * - current_episode_playlist: episode queue array
   * - PLAYLIST_DATA: parentData with type=PODCAST (for syncQueueFromAuto detection)
   */
  private fun storePodcastLocalData(extras: Bundle, episodeId: String?) {
    val episodeJson = JSONObject().apply {
      put("id", extras.getString("id") ?: episodeId ?: "")
      put("title", extras.getString("title") ?: "")
      put("showId", extras.getString("showId") ?: "")
      put("showTitle", extras.getString("artist") ?: "")
      put("duration", extras.getString("length") ?: "0")
      put("durationMs", extras.getLong("durationMs", 0))
      put("image", extras.getString("image") ?: "")
      put("isPodcast", true)
      val enclosureUrl = extras.getString("enclosure_url")
      if (!enclosureUrl.isNullOrEmpty() && enclosureUrl != "null") {
        put("enclosure", JSONObject().apply {
          put("url", enclosureUrl)
          put("type", "audio/mpeg")
        })
      }
    }

    // Write current episode
    LocalStorageUtils.storeInFile(context, "current_episode", episodeJson.toString())

    // Write episode playlist from queue
    val queue = mediaSession.controller.queue
    if (queue != null) {
      val episodeList = queue.mapNotNull { item ->
        val itemExtras = item.description.extras ?: return@mapNotNull null
        val itemType = itemExtras.getString("media_type") ?: ""
        if (itemType == "podcast_episode" || itemType == "podcastEpisode") {
          JSONObject().apply {
            put("id", itemExtras.getString("id") ?: "")
            put("title", itemExtras.getString("title") ?: "")
            put("showId", itemExtras.getString("showId") ?: "")
            put("showTitle", itemExtras.getString("artist") ?: "")
            put("duration", itemExtras.getString("length") ?: "0")
            put("durationMs", itemExtras.getLong("durationMs", 0))
            put("image", itemExtras.getString("image") ?: "")
            put("isPodcast", true)
            val url = itemExtras.getString("enclosure_url")
            if (!url.isNullOrEmpty() && url != "null") {
              put("enclosure", JSONObject().apply {
                put("url", url)
                put("type", "audio/mpeg")
              })
            }
          }
        } else null
      }
      LocalStorageUtils.storeInFile(context, "current_episode_playlist",
        org.json.JSONArray(episodeList).toString())
    }

    // Write PLAYLIST_DATA so syncQueueFromAuto can detect podcast type
    val playlistData = extras.getString("parentData")
    LocalStorageUtils.storeInFile(context, PLAYLIST_DATA, playlistData)

    CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE)
  }

  private fun storeLocalData(extras: Bundle, trackId: String?) {
    if(mediaSession.controller.queue !== null) {
      val stringQueue = mediaSession.controller.queue.map { it ->
        "{ \"data\":" + it.description.extras?.getString("track") + " }"
      }
      val playlistData = extras.getString("parentData")
      LocalStorageUtils.storeInFile(context, QUEUE_ITEMS_KEY, stringQueue.toString())
      LocalStorageUtils.storeInFile(context, PLAYLIST_DATA, playlistData)
      LocalStorageUtils.storeDataInPrefs(context, CURRENT_TRACK_KEY, trackId.toString())

      CordovaEventBridge.sendEvent(CordovaEvents.ON_MEDIA_UPDATE)
    }
  }

  private fun updateState(
    state: Int,
    position: Long = mediaPlayer.currentPosition
  ) {
    //Log.i(TAG, "[MediaSessionCallback] Update state $state")
    val actions = (
      PlaybackStateCompat.ACTION_PLAY or
        PlaybackStateCompat.ACTION_PAUSE or
        PlaybackStateCompat.ACTION_PLAY_PAUSE or
        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
        PlaybackStateCompat.ACTION_SEEK_TO or
        PlaybackStateCompat.ACTION_SKIP_TO_QUEUE_ITEM
      )
    val pb = PlaybackStateCompat.Builder()
      .setActions(actions)
      .setState(state, position, 1f)
      .build()
    mediaSession.setPlaybackState(pb)

    // Notify preloader about buffering state changes
    TrackPreloader.onPlaybackStateChanged(state == PlaybackStateCompat.STATE_BUFFERING)
  }

  private fun handlePrepare() {
    // Sync the queue index with the current track
    val currentMediaId = mediaSession.controller.metadata?.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID)
    QueueManager.syncCurrentIndex(mediaSession, currentMediaId)
    // Hay un pedido más nuevo resolviendo su URL: este tema es viejo (por ejemplo el del prepare de la conexión) y los
    // flags son del pedido nuevo. Queda preparado sin sonar ni avisar; playCurrentTrack lo reemplaza al llegar la URL.
    if (loadPending) {
      Log.i(TAG, "[HANDLE_PREPARE] preparado un tema viejo con el pedido $loadGeneration abierto: no arranca")
      return
    }
    // Sin Android Auto el player nativo no tiene que sonar (sería por el parlante del teléfono): por ejemplo un tema
    // que terminó de prepararse después de la desconexión. Queda preparado y en pausa.
    if (!MediaControlBridge.androidAutoConnected) {
      mediaPlayer.shouldAutoPlayOnPrepare = false
      mediaPlayer.currentTrackFromApp = true
    }
    Log.i(TAG, "[HANDLE_PREPARE] ${when {
      mediaPlayer.shouldAutoPlayOnPrepare -> "autoplay"
      mediaPlayer.currentTrackFromApp -> "en pausa (prepare de la conexión o sin Android Auto)"
      else -> "elegido en el auto"
    }} mediaId=$currentMediaId")

    // Check if we should auto-play (explicitly requested from app)
    if(mediaPlayer.shouldAutoPlayOnPrepare) {
      mediaPlayer.shouldAutoPlayOnPrepare = false
      mediaPlayer.currentTrackFromApp = false

      // Request audio focus before starting playback
      val hasFocus = mediaPlayer.requestAudioFocusForPlayback()

      if (hasFocus) {
        mediaPlayer.start()
        updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        showNotification(PlaybackStateCompat.STATE_PLAYING)
        emitPlaybackState("play", "prepared")
      } else {
        Log.w(TAG, "[HANDLE_PREPARE_NO_FOCUS_AUTO] Could not gain audio focus for auto-play, setting to PAUSED")
        updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
        showNotification(PlaybackStateCompat.STATE_PAUSED)
        emitPrepareWithoutFocus()
      }
    } else if(mediaPlayer.currentTrackFromApp) {
      // Track from app but no auto-play - just prepare and leave in STOPPED state
      mediaPlayer.currentTrackFromApp = false
      updateState(PlaybackStateCompat.STATE_STOPPED, mediaPlayer.currentPosition)
      // Antes de llegar acá, onPlayFromMediaId / startPlaybackWithInitialTracks publicaron la notificación en
      // PLAYING (ongoing, con "Pausa") sin que vaya a sonar nada: se la deja en pausa, lista para reproducir.
      showNotification(PlaybackStateCompat.STATE_PAUSED)
      // 'pause' y no 'stop': el JS viejo sólo mueve el botón con play/pause.
      emitPlaybackState("pause", "prepared_idle")
    } else {
      // Normal playback from Android Auto (e.g., user clicked a song)
      // Request audio focus again right before starting playback
      // This helps prevent race conditions with audio focus loss
      val hasFocus = mediaPlayer.requestAudioFocusForPlayback()

      if (hasFocus) {
        mediaPlayer.start()
        updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
        handler.post(updatePlaybackPositionRunnable)
        mediaSession.isActive = true
        showNotification(PlaybackStateCompat.STATE_PLAYING)
        // Como onPlay: sin este aviso el player del app no se enteraba de que el tema elegido en el auto sonaba.
        emitPlaybackState("play", "prepared")
      } else {
        Log.w(TAG, "[HANDLE_PREPARE_NO_FOCUS] Could not gain audio focus, playback not started")
        updateState(PlaybackStateCompat.STATE_PAUSED, mediaPlayer.currentPosition)
        showNotification(PlaybackStateCompat.STATE_PAUSED)
        emitPrepareWithoutFocus()
      }
    }
  }

  private fun handleError(what: Int, extra: Int) {
    var userFacingMessage = "An unknown error occurred during playback."
    val logMessage = StringBuilder("MediaPlayer Error: ")
    var shouldRecreatePlayer = false

    when (what) {
      MediaPlayer.MEDIA_ERROR_UNKNOWN -> {
        logMessage.append("UNKNOWN_ERROR")
        when (extra) {
          MediaPlayer.MEDIA_ERROR_IO -> {
            userFacingMessage = "Could not load the track. Please check your internet connection or try again."
            logMessage.append(" (IO Error - Network/File issue)")
          }
          MediaPlayer.MEDIA_ERROR_MALFORMED -> {
            userFacingMessage = "The track is corrupted or not in a recognizable format."
            logMessage.append(" (Malformed Media)")
          }
          MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> {
            userFacingMessage = "This media format is not supported."
            logMessage.append(" (Unsupported Media)")
          }
          MediaPlayer.MEDIA_ERROR_TIMED_OUT -> {
            userFacingMessage = "Playback timed out. Check your connection."
            logMessage.append(" (Timed Out)")
          }
          else -> {
            userFacingMessage = "An unexpected error occurred."
            logMessage.append(" (Extra: $extra)")
          }
        }
      }
      MediaPlayer.MEDIA_ERROR_SERVER_DIED -> {
        userFacingMessage = "The media playback system encountered a critical error. Please restart the app."
        logMessage.append("SERVER_DIED - Critical error, player needs full re-initialization.")
        shouldRecreatePlayer = true
      }
      else -> {
        userFacingMessage = "Playback failed. Please try a different track."
        logMessage.append(" (What: $what, Extra: $extra)")
      }
    }

    Log.e(TAG, logMessage.toString())

    // 1. Stop periodic position updates immediately
    handler.removeCallbacks(updatePlaybackPositionRunnable)

    // 2. Manage MediaPlayer state
    try {
      mediaPlayer.stop() // Stop any current playback
      if (shouldRecreatePlayer) {
        mediaPlayer.release()
      } else {
        mediaPlayer.reset() // Reset to Idle for reuse
      }
    } catch (e: IllegalStateException) {
      Log.e("MyPlaybackService", "Error during player cleanup after error: ${e.message}")
      // Fallback to full release if reset fails
      mediaPlayer.release()
    }

    // 3. Update MediaSessionCompat state to ERROR
    // Crucial to inform external controllers about the problem
    val errorMessageState = PlaybackStateCompat.Builder()
      .setState(PlaybackStateCompat.STATE_ERROR, 0, 1.0f)
      .setErrorMessage(PlaybackStateCompat.ERROR_CODE_UNKNOWN_ERROR, userFacingMessage) // Provide user-friendly message
      .setActions(0) // No actions available when in error state
      .build()
    mediaSession.setPlaybackState(errorMessageState)
    // La notificación seguía en PLAYING (ongoing, cronómetro) después del error.
    showNotification(PlaybackStateCompat.STATE_PAUSED)
    cancelFocusResume()
    // El tema que fallaba ya no se prepara: los flags no pasan al próximo prepare (el de una reconexión arrancaría solo).
    // Con un pedido abierto los flags son de ese pedido y no se tocan.
    if (!loadPending) {
      mediaPlayer.shouldAutoPlayOnPrepare = false
      mediaPlayer.currentTrackFromApp = false
    }
    // getCurrentPlaybackState da "unknown" (STATE_ERROR): el JS lo toma como pausa.
    emitPlaybackState("pause", "error")


    // 4. (Optional) Inform the user in the main UI
    // You'd typically use a broadcast or EventBus to send this message to your Activity/Fragment
    // Example (requires LocalBroadcastManager setup or similar):
    // val errorIntent = Intent("my_app.playback_error")
    // errorIntent.putExtra("message", userFacingMessage)
    // LocalBroadcastManager.getInstance(applicationContext).sendBroadcast(errorIntent)

    // 5. (Optional) Implement recovery logic
    // For example, if you have a playlist and the current track failed,
    // you might try to skip to the next one automatically.
    // For this, you would need to manage your playlist index.
    // skipToNextTrackIfAvailable() // Your custom function
  }

  private fun handleAudioFocusChange(focusChange: Int) {
    // Una línea por aviso: es la única forma de saber qué pérdida manda cada fuente (voz de Auto, llamada, navegación).
    Log.i(TAG, "[FOCUS] change=$focusChange playing=${mediaPlayer.isPlaying()} resumeOnGain=$resumeOnFocusGain " +
      "auto=${MediaControlBridge.androidAutoConnected}")
    when (focusChange) {
      android.media.AudioManager.AUDIOFOCUS_GAIN -> {
        if (mediaPlayer.isPlaying()) {
          // When we regain audio focus, immediately update the state to PLAYING
          // This prevents Android Auto from auto-pausing after we regain focus
          updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
          handler.removeCallbacks(updatePlaybackPositionRunnable)
          handler.post(updatePlaybackPositionRunnable)
          mediaSession.isActive = true
        } else if (resumeOnFocusGain) {
          val speakerOnlyBefore = speakerOnlyWhenArmed
          disarmFocusResume()
          resumeAfterFocusGain(speakerOnlyBefore)
        }
      }
      android.media.AudioManager.AUDIOFOCUS_LOSS -> {
        // Permanente (otra app de música, YouTube, un GAIN de gearhead): no se reanuda nunca solo.
        disarmFocusResume()
        if (mediaPlayer.isPlaying()) {
          pauseForFocusLoss("focus_loss")
        }
      }
      android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
      android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
        // Transitoria (llamada, voz). CAN_DUCK casi nunca llega (setWillPauseWhenDucked(false): el sistema baja el
        // volumen solo); si llega, se pausa como antes. Sólo se marca si sonaba: pausa del usuario + llamada no reanuda.
        if (mediaPlayer.isPlaying()) {
          armFocusResume()
          pauseForFocusLoss(
            if (focusChange == android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) "focus_loss_transient"
            else "focus_loss_duck")
        }
      }
    }
  }

  // Pausa por pérdida de foco: igual que onPause (notificación en pausa y aviso al JS). La posición se lee antes de
  // pausar: con el player en pausa el adapter devuelve 0 y el auto mostraría 0:00.
  private fun pauseForFocusLoss(reason: String) {
    val position = mediaPlayer.currentPosition
    mediaPlayer.pause()
    updateState(PlaybackStateCompat.STATE_PAUSED, position)
    handler.removeCallbacks(updatePlaybackPositionRunnable)
    showNotification(PlaybackStateCompat.STATE_PAUSED)
    emitPlaybackState("pause", reason)
  }

  // GAIN = nuestra entrada volvió arriba de la pila: no se vuelve a pedir foco (Android 15 lo niega a un app que no
  // está al frente ni tiene FGS, y no hace falta). No se reanuda si el auto ya no está o si la música saldría por el
  // parlante del teléfono (el auto se desconectó durante la llamada).
  private fun resumeAfterFocusGain(speakerOnlyBefore: Boolean) {
    if (released || mediaPlayer.isPreparing() || !mediaPlayer.isPrepared || !MediaControlBridge.androidAutoConnected) {
      Log.i(TAG, "[FOCUS] GAIN: no se reanuda (released=$released prepared=${mediaPlayer.isPrepared} " +
        "auto=${MediaControlBridge.androidAutoConnected})")
      return
    }
    // Sólo si la salida CAMBIÓ a parlante desde que se armó: un equipo que reporta parlante también durante la
    // proyección de Auto no queda sin reanudar.
    if (!speakerOnlyBefore && mediaRouteIsPhoneSpeaker()) {
      Log.i(TAG, "[FOCUS] GAIN: no se reanuda, la salida de medios pasó al parlante del teléfono")
      return
    }
    mediaPlayer.play()
    if (!mediaPlayer.isPlaying()) {
      Log.w(TAG, "[FOCUS] GAIN: play() no arrancó, queda en pausa")
      return
    }
    Log.i(TAG, "[FOCUS] GAIN después de una pérdida transitoria o un foco diferido: se reanuda")
    updateState(PlaybackStateCompat.STATE_PLAYING, mediaPlayer.currentPosition)
    handler.removeCallbacks(updatePlaybackPositionRunnable)
    handler.post(updatePlaybackPositionRunnable)
    mediaSession.isActive = true
    showNotification(PlaybackStateCompat.STATE_PLAYING)
    emitPlaybackState("play", "focus_gain")
  }

  // API 33+: true si la música de esta app saldría sólo por el parlante del teléfono. Sin la API, o si falla, false:
  // queda la guarda de androidAutoConnected.
  private fun mediaRouteIsPhoneSpeaker(): Boolean {
    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return false
    return try {
      val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
      val attributes = android.media.AudioAttributes.Builder()
        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
      val devices = audioManager.getAudioDevicesForAttributes(attributes)
      Log.i(TAG, "[FOCUS] salida de medios: ${devices.map { it.type }}")
      devices.isNotEmpty() && devices.all { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
    } catch (e: Exception) {
      Log.w(TAG, "[FOCUS] no se pudo leer la salida de medios: ${e.message}")
      false
    }
  }

  private fun cancelFocusResume() {
    if (resumeOnFocusGain) Log.i(TAG, "[FOCUS] reanudación pendiente cancelada por un comando")
    disarmFocusResume()
  }

  private fun armFocusResume() {
    resumeOnFocusGain = true
    speakerOnlyWhenArmed = mediaRouteIsPhoneSpeaker()
    if (!noisyReceiverRegistered) {
      try {
        ContextCompat.registerReceiver(
          context, noisyReceiver,
          IntentFilter(android.media.AudioManager.ACTION_AUDIO_BECOMING_NOISY),
          ContextCompat.RECEIVER_NOT_EXPORTED)
        noisyReceiverRegistered = true
      } catch (e: Exception) {
        Log.w(TAG, "[FOCUS] no se pudo registrar BECOMING_NOISY: ${e.message}")
      }
    }
  }

  private fun disarmFocusResume() {
    resumeOnFocusGain = false
    if (noisyReceiverRegistered) {
      noisyReceiverRegistered = false
      try {
        context.unregisterReceiver(noisyReceiver)
      } catch (e: Exception) {
        Log.w(TAG, "[FOCUS] no se pudo desregistrar BECOMING_NOISY: ${e.message}")
      }
    }
  }

  // Sin foco (onPlay, handlePrepare). Con el foco diferido (una llamada en curso) el usuario quiere que suene:
  // arranca cuando llegue el GAIN, si el player está listo para start(). Sin este aviso el JS quedaba esperando un
  // 'play' que no llega.
  private fun emitPrepareWithoutFocus() {
    if (mediaPlayer.lastFocusRequestDelayed && mediaPlayer.isPrepared) {
      armFocusResume()
      emitPlaybackState("pause", "focus_delayed")
    } else {
      emitPlaybackState("pause", "no_focus")
    }
  }

  // `reason` es sólo diagnóstico: el JS viejo y el nuevo ignoran los campos que no conocen.
  private fun emitPlaybackState(action: String, reason: String) {
    CordovaEventBridge.sendEvent(
      CordovaEvents.ON_PLAYBACK_STATE_CHANGED,
      JSONObject().put("action", action).put("reason", reason))
  }

  private fun handlePlaybackCompletion() {
    mediaPlayer.stop()
    mediaPlayer.reset()
    updateState(PlaybackStateCompat.STATE_STOPPED, 0)
    handler.removeCallbacks(updatePlaybackPositionRunnable)
    // El usuario eligió otro tema y se está cargando: ése es el que sigue, no el siguiente de la cola vieja.
    if (loadPending) {
      Log.i(TAG, "[PREPARE] fin de tema con el pedido $loadGeneration abierto: no se salta")
      return
    }
    onSkipToNext()
  }

  private val updatePlaybackPositionRunnable: Runnable = object : Runnable {
    override fun run() {
      try {
        if (mediaPlayer.isPlaying()) {
        //  Log.i(TAG, "[MediaSessionCallback] Update Playback position, player is playing")
          val currentPosition = mediaPlayer.currentPosition
          val currentState =
            PlaybackStateCompat.STATE_PLAYING

          updateState(currentState, currentPosition)
        }
        handler.postDelayed(this, PLAYBACK_POSITION_UPDATE_INTERVAL)
      } catch (e: Exception) {
        // Prevent app to break when disconnected.
      }

    }
  }

  private fun showNotification(state: Int) {
    // Después de onDestroy no se publica nada (p. ej. la corrutina de onPlayFromMediaId que
    // vuelve a Main tarde): el cancel(1) del servicio ya corrió y nadie más la sacaría.
    if (released) return
    val seq = ++notificationSeq

    val controller = mediaSession.controller
    val mediaMetadata = controller.metadata
    val description = mediaMetadata?.description

    // Sin gate de POST_NOTIFICATIONS a propósito. Una notificación MediaStyle con el token de la
    // sesión es una "notificación de medios" y Android 13+ la publica aunque el permiso esté
    // denegado (NotificationManagerService: isMediaNotification()); el fork de music-controls hace
    // lo mismo. El return que había acá dejaba al teléfono sin controles con Auto conectado en los
    // binarios que nunca piden el permiso (Claro, demos, dev).
    logNotificationPermissionOnce()

    // Create notification channel for API 26+
    val channelName = "Media Playback"
    val channelDescription = "Media playback controls"
    val importance = NotificationManager.IMPORTANCE_LOW
    val channel = NotificationChannel(CHANNEL_ID, channelName, importance)
    channel.description = channelDescription
    val notificationManager = context.getSystemService(NotificationManager::class.java)
    notificationManager.createNotificationChannel(channel)

    val mainActivityIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
    val contentIntent = PendingIntent.getActivity(
      context, 0, mainActivityIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val builder = NotificationCompat.Builder(context, CHANNEL_ID).apply {
      setContentTitle(description?.title)
      setContentText(description?.subtitle)
      setSubText(description?.description)
      setContentIntent(contentIntent)
      setSmallIcon(context.applicationInfo.icon)
      setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      if (state == PlaybackStateCompat.STATE_PLAYING) {
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_previous, "Previous",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_pause, "Pause",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_PAUSE)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_next, "Next",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
        ))
      } else {
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_previous, "Previous",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_play, "Play",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_PLAY)
        ))
        addAction(NotificationCompat.Action(
          android.R.drawable.ic_media_next, "Next",
          MediaButtonReceiver.buildMediaButtonPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
        ))
      }
      setStyle(androidx.media.app.NotificationCompat.MediaStyle()
        .setMediaSession(mediaSession.sessionToken)
        .setShowActionsInCompactView(0, 1, 2))
      setWhen(System.currentTimeMillis() - (mediaPlayer.currentPosition))
      setUsesChronometer(state == PlaybackStateCompat.STATE_PLAYING)
      setOngoing(state == PlaybackStateCompat.STATE_PLAYING)
    }

    val imageUri = description?.iconUri
    val imageUrl = imageUri?.toString()
    if (imageUrl != null) {
      CoroutineScope(Dispatchers.IO).launch {
        try {
          // Check if this is a local FileProvider URI
          val isFileProvider = imageUrl.startsWith("content://") &&
                               (imageUrl.contains(".fileprovider") ||
                                imageUrl.contains(".auto.file.provider") ||
                                imageUrl.contains(".cdv.core.file.provider"))

          val bitmap = if (isFileProvider) {
            // Grant permission to system UI for notification
            try {
              context.grantUriPermission(
                "com.android.systemui",
                imageUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
              )
            } catch (e: Exception) {
              Log.w(TAG, "[NOTIFICATION_IMAGE_PERMISSION_WARN] Could not grant permission to systemui: ${e.message}")
            }

            // Load bitmap from ContentResolver
            context.contentResolver.openInputStream(imageUri)?.use { inputStream ->
              BitmapFactory.decodeStream(inputStream)
            } ?: run {
              Log.w(TAG, "[NOTIFICATION_IMAGE_LOAD_FAILED] Could not open InputStream for local image")
              null
            }
          } else {
            // Remote image - load from URL
            val connection = URL(imageUrl).openConnection()
            connection.connectTimeout = 5000
            connection.readTimeout = 10000
            connection.getInputStream().use { BitmapFactory.decodeStream(it) }
          }

          if (bitmap != null) {
            withContext(Dispatchers.Main) {
              // Llegó tarde: ya hay una notificación más nueva, o el servicio se destruyó.
              if (!released && seq == notificationSeq) {
                builder.setLargeIcon(bitmap)
                safelyShowNotification(NOTIFICATION_ID, builder.build())
              }
            }
          } else {
            Log.w(TAG, "[NOTIFICATION_IMAGE_NULL] Bitmap is null, showing notification without image")
          }
        } catch (e: Throwable) {
          // Throwable: un OutOfMemoryError al decodificar la carátula (equipos de 2 GB) no puede tirar el proceso.
          Log.e(TAG, "[NOTIFICATION_IMAGE_ERROR] Error loading notification image: ${e.message}", e)
          Log.e(TAG, "[NOTIFICATION_IMAGE_STACK_TRACE] ${e.stackTraceToString()}")
        }
      }
    }
    val notification = builder.build()
    safelyShowNotification(NOTIFICATION_ID, notification)

    // Only call startForeground if permission is granted
    if (state == PlaybackStateCompat.STATE_PLAYING && context is Service) {
      try {
        context.startForeground(NOTIFICATION_ID, notification)
      } catch (e: SecurityException) {
        Log.w(TAG, "No notification permission for startForeground", e)
      }
    } else if (context is Service) {
      context.stopForeground(false)
    }
  }


  // Publica o actualiza la notificación. Sin gate de permiso: ver showNotification(). Con el
  // permiso denegado, Android 13+ igual la acepta por ser de medios; si algún OEM la rechazara,
  // NotificationManagerService la descarta en silencio (no tira), y el try es sólo defensivo.
  @SuppressLint("MissingPermission")
  private fun safelyShowNotification(notificationId: Int, notification: android.app.Notification) {
    try {
      NotificationManagerCompat.from(context).notify(notificationId, notification)
    } catch (e: Exception) {
      Log.w(TAG, "[NOTIFICATION] notify falló: ${e.javaClass.name}: ${e.message}")
    }
  }

  // Una línea por instancia del servicio, para leer el logcat de QA sin adivinar el permiso.
  private fun logNotificationPermissionOnce() {
    if (loggedNotificationPermission) return
    loggedNotificationPermission = true
    val granted = android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU ||
      context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
      android.content.pm.PackageManager.PERMISSION_GRANTED
    Log.i(TAG, "[NOTIFICATION] POST_NOTIFICATIONS=${if (granted) "concedido" else "denegado (se publica igual: notificación de medios)"}")
  }

  /**
   * Lo llama MusicLibraryService.onDestroy() ANTES de liberar la sesión y del cancel(1): después
   * de esto nada vuelve a publicar el id 1 (carátula tardía, corrutinas de onPlayFromMediaId /
   * playQueueItem que vuelven a Main) y se corta el runnable de posición, que se re-posteaba cada
   * segundo para siempre reteniendo el callback muerto.
   */
  fun release() {
    released = true
    disarmFocusResume()
    notificationSeq++
    loadGeneration++
    loadPending = false
    handler.removeCallbacks(updatePlaybackPositionRunnable)
  }

  // Android Auto se desconectó: un tema que se estaba cargando ya no arranca (sonaría por el parlante del teléfono).
  fun onAutoDisconnected() {
    val hadPending = loadPending
    if (loadPending || mediaPlayer.shouldAutoPlayOnPrepare) {
      Log.i(TAG, "[PREPARE] desconexión con el pedido $loadGeneration abierto: no arranca")
    }
    loadGeneration++
    loadPending = false
    mediaPlayer.shouldAutoPlayOnPrepare = false
    // Un prepareAsync en curso termina en pausa (handlePrepare sin auto conectado); un pedido descartado no deja la
    // sesión en BUFFERING con la notificación en "reproduciendo".
    if (hadPending && !mediaPlayer.isPlaying()) {
      handler.removeCallbacks(updatePlaybackPositionRunnable)
      updateState(PlaybackStateCompat.STATE_PAUSED, 0)
      showNotification(PlaybackStateCompat.STATE_PAUSED)
    }
  }

  private fun beginTrackLoad(source: String): Int {
    val gen = ++loadGeneration
    loadPending = true
    loadStartedAt = SystemClock.elapsedRealtime()
    Log.i(TAG, "[PREPARE] pedido $gen ($source) autoplay=${mediaPlayer.shouldAutoPlayOnPrepare} " +
      "fromApp=${mediaPlayer.currentTrackFromApp}")
    return gen
  }

  // En el main thread. false: un pedido más nuevo lo reemplazó (o se liberó el servicio) y no se aplica.
  private fun isCurrentLoad(gen: Int, where: String): Boolean {
    if (released || gen != loadGeneration) {
      Log.i(TAG, "[PREPARE] pedido $gen descartado en $where: " +
        if (released) "el servicio se liberó" else "hay uno más nuevo ($loadGeneration)")
      return false
    }
    return true
  }

  // El pedido llegó al player: con URL, prepareAsync ya puso isPreparing; sin URL, queda en pausa.
  private fun endTrackLoad(gen: Int, uri: Uri?) {
    loadPending = false
    Log.i(TAG, "[PREPARE] pedido $gen uri=${if (uri == null) "null" else "ok"} " +
      "${SystemClock.elapsedRealtime() - loadStartedAt} ms autoplay=${mediaPlayer.shouldAutoPlayOnPrepare} " +
      "fromApp=${mediaPlayer.currentTrackFromApp}")
  }

  // Sin URL (sin red y sin descarga, un id inválido, error del BE): en pausa y avisado, en lugar de BUFFERING con la
  // notificación en "reproduciendo" sin que suene nada. Nadie lo va a preparar: los flags se apagan para que no
  // arranque solo el próximo prepare (el de una reconexión).
  private fun endWithoutMedia() {
    mediaPlayer.shouldAutoPlayOnPrepare = false
    // Con un prepareAsync anterior todavía en curso (el pedido nuevo murió antes de playCurrentTrack, que lo hubiera
    // cancelado), ese tema termina en pausa en handlePrepare en lugar de sonar solo.
    mediaPlayer.currentTrackFromApp = mediaPlayer.isPreparing()
    // Si sigue sonando el tema anterior (el pedido murió antes de playCurrentTrack, que lo hubiera parado), la sesión
    // no se pone en pausa con el audio saliendo: sólo se apagan los flags.
    if (mediaPlayer.isPlaying()) return
    handler.removeCallbacks(updatePlaybackPositionRunnable)
    updateState(PlaybackStateCompat.STATE_PAUSED, 0)
    showNotification(PlaybackStateCompat.STATE_PAUSED)
    emitPlaybackState("pause", "no_media")
  }

  // El pedido murió antes de la URL (error de red al pedir la lista, lista vacía): deja de estar abierto. Se puede
  // llamar desde IO. Si sigue sonando el tema anterior (playCurrentTrack no llegó a pararlo) sólo se apagan los flags.
  private fun abandonTrackLoad(gen: Int) {
    handler.post {
      if (gen == loadGeneration && loadPending) {
        Log.w(TAG, "[PREPARE] pedido $gen terminó sin tema (antes de la URL)")
        loadPending = false
        endWithoutMedia()
      }
    }
  }

}
