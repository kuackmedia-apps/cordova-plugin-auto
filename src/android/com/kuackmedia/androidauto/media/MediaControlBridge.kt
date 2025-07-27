package com.kuackmedia.androidauto.media

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
        mediaSession?.controller?.transportControls?.prepare()
    }
}