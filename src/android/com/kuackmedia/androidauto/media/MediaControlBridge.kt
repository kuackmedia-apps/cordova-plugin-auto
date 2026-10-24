package com.kuackmedia.androidauto.media

import android.os.Handler
import android.os.Looper
import android.support.v4.media.session.MediaSessionCompat

object MediaControlBridge {
    var mediaSession: MediaSessionCompat? = null
    var mediaPlayer: IPlayerAdapter? = null
    var androidAutoConnected = false

    fun play() {
        mediaSession?.controller?.transportControls?.play()
    }

    fun pause() {
        mediaSession?.controller?.transportControls?.pause()
    }

    fun setConnected(flag: Boolean) {
        this.androidAutoConnected = flag
    }

    // Posición inicial (ms) que mandó el app con playCurrentTrack: la del teléfono en el traspaso teléfono → auto. La toma
    // el próximo onPrepare (takePendingStartPosition) y vale sólo para el pedido que abre. Sólo en el main thread.
    private var pendingStartPositionMs = 0L

    fun playCurrentTrack(startPositionMs: Long = 0L) {
        // Lo llama el JS desde el hilo del bridge (JavaBridge): el flag se escribe en el main thread, en orden con el
        // resto de la sesión (onPlayFromMediaId, onPlay, handlePrepare también lo escriben ahí).
        Handler(Looper.getMainLooper()).post {
            // Set flag to enable auto-play after preparation
            mediaPlayer?.shouldAutoPlayOnPrepare = true
            pendingStartPositionMs = if (startPositionMs > 0) startPositionMs else 0L
            mediaSession?.controller?.transportControls?.prepare()
        }
    }

    fun takePendingStartPosition(): Long {
        val start = pendingStartPositionMs
        pendingStartPositionMs = 0L
        return start
    }
}
