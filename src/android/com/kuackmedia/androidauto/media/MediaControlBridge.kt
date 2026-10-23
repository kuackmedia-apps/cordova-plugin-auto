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

    fun playCurrentTrack() {
        // Lo llama el JS desde el hilo del bridge (JavaBridge): el flag se escribe en el main thread, en orden con el
        // resto de la sesión (onPlayFromMediaId, onPlay, handlePrepare también lo escriben ahí).
        Handler(Looper.getMainLooper()).post {
            // Set flag to enable auto-play after preparation
            mediaPlayer?.shouldAutoPlayOnPrepare = true
            mediaSession?.controller?.transportControls?.prepare()
        }
    }
}
