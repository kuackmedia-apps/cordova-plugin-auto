package org.apache.cordova.myplugin;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.json.JSONArray;
import org.json.JSONException;
import android.support.v4.media.MediaMetadataCompat;

public class MyMusicPlugin extends CordovaPlugin {

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if ("setMetadata".equals(action)) {
            String title = args.getString(0);
            String artist = args.getString(1);
            String album = args.getString(2);

            setMetadata(title, artist, album);

            callbackContext.success();
            return true;
        }
        return false;
    }

    private void setMetadata(String title, String artist, String album) {
        if (MyMusicService.getMediaSession() == null) return;

        MediaMetadataCompat metadata = new MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            // You can add more fields if you want
            .build();

        MyMusicService.getMediaSession().setMetadata(metadata);
    }
}
