package org.apache.cordova.myplugin;

import android.os.Bundle;
import androidx.media.MediaBrowserServiceCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.MediaBrowserCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import java.util.ArrayList;
import java.util.List;
import android.util.Log;

public class MyMusicService extends MediaBrowserServiceCompat {
    private static MediaSessionCompat mediaSession;

    public static MediaSessionCompat getMediaSession() {
      return mediaSession;
    }


    @Override
    public void onCreate() {
        Log.d("MyMediaBrowserService", "SERVICE STARTED!");
        super.onCreate();
        mediaSession = new MediaSessionCompat(this, "MyMusicService");
        setSessionToken(mediaSession.getSessionToken());

        PlaybackStateCompat state = new PlaybackStateCompat.Builder()
        .setActions(
            PlaybackStateCompat.ACTION_PLAY |
            PlaybackStateCompat.ACTION_PAUSE |
            PlaybackStateCompat.ACTION_PLAY_PAUSE
        )
        .setState(PlaybackStateCompat.STATE_PAUSED, 0, 1.0f)
        .build();

        mediaSession.setPlaybackState(state);
        mediaSession.setCallback(new MyMediaSessionManager());
        mediaSession.setActive(true);
    }

    @Override
    public BrowserRoot onGetRoot(String clientPackageName, int clientUid, Bundle rootHints) {
        return new BrowserRoot("root_id", null);
    }

    @Override
    public void onLoadChildren(String parentId, Result<List<MediaBrowserCompat.MediaItem>> result) {
        List<MediaBrowserCompat.MediaItem> mediaItems = new ArrayList<>();

        MediaDescriptionCompat description = new MediaDescriptionCompat.Builder()
                .setMediaId("1")
                .setTitle("Example Song")
                .setSubtitle("Example Artist")
                .build();

        mediaItems.add(new MediaBrowserCompat.MediaItem(description, MediaBrowserCompat.MediaItem.FLAG_PLAYABLE));
        result.sendResult(mediaItems);
    }
}
