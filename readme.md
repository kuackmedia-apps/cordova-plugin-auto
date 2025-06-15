# Cordova Plugin Auto

A Cordova plugin that enables your application to run in Apple CarPlay and Android Auto using music playlists.

## Overview

This plugin allows Cordova applications to integrate with vehicle infotainment systems through Apple CarPlay and Android Auto platforms. It provides a unified API to create and manage music playlists that can be controlled through the vehicle's native interface.

## Features

- Seamless integration with Apple CarPlay and Android Auto
- Music playlist creation and management
- Playback controls through vehicle interface
- Cross-platform support (iOS and Android)
- Simple JavaScript API for Cordova applications

## Installation

```bash
cordova plugin add cordova-plugin-auto
```

Or install directly from GitHub:

```bash
cordova plugin add https://github.com/fmaceachen/cordova-plugin-auto.git
```

## Platform Requirements

### iOS
- iOS 14.0+
- Xcode 12.0+
- CarPlay entitlement in your Apple Developer account

### Android
- Android 6.0+ (API level 23+)
- Android Auto SDK

## Configuration

### iOS Configuration

Add the following to your app's `config.xml`:

```xml
<platform name="ios">
    <config-file parent="UIBackgroundModes" target="*-Info.plist">
        <array>
            <string>audio</string>
        </array>
    </config-file>
    <config-file parent="NSUserActivityTypes" target="*-Info.plist">
        <array>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER).playback</string>
        </array>
    </config-file>
</platform>
```

You must also have the CarPlay entitlement enabled in your Apple Developer account and provisioning profile.

### Android Configuration

Add the following to your app's `config.xml`:

```xml
<platform name="android">
    <config-file parent="/manifest/application" target="AndroidManifest.xml">
        <meta-data
            android:name="com.google.android.gms.car.application"
            android:resource="@xml/automotive_app_desc" />
    </config-file>
</platform>
```

## Usage

```javascript
// Initialize the plugin
document.addEventListener('deviceready', function() {
    // Check if Auto interfaces are available
    CordovaAuto.isAvailable(function(available) {
        if (available) {
            console.log('CarPlay/Android Auto is available');
        }
    });
    
    // Create a playlist
    var playlist = {
        id: 'playlist1',
        title: 'My Playlist',
        artwork: 'https://example.com/artwork.jpg',
        tracks: [
            {
                id: 'track1',
                title: 'Song Title',
                artist: 'Artist Name',
                album: 'Album Name',
                artwork: 'https://example.com/track1.jpg',
                url: 'https://example.com/track1.mp3',
                duration: 180 // in seconds
            }
            // Add more tracks as needed
        ]
    };
    
    // Set the active playlist
    CordovaAuto.setPlaylist(playlist, function() {
        console.log('Playlist set successfully');
    }, function(error) {
        console.error('Error setting playlist:', error);
    });
    
    // Listen for playback commands from the car interface
    CordovaAuto.onPlaybackCommand(function(command) {
        switch(command) {
            case 'play':
                // Start playback
                break;
            case 'pause':
                // Pause playback
                break;
            case 'next':
                // Skip to next track
                break;
            case 'previous':
                // Go to previous track
                break;
        }
    });
}, false);
```

## API Reference

### Methods

#### isAvailable(successCallback, errorCallback)
Checks if CarPlay/Android Auto is available on the device.

#### setPlaylist(playlist, successCallback, errorCallback)
Sets the current playlist to be displayed in the car interface.

#### updatePlaybackStatus(status, successCallback, errorCallback)
Updates the current playback status (playing, paused, etc.).

#### updateTrackInfo(trackInfo, successCallback, errorCallback)
Updates the currently playing track information.

### Events

#### onPlaybackCommand(callback)
Receives playback commands from the car interface (play, pause, next, previous).

#### onConnectionChange(callback)
Notifies when the connection to CarPlay/Android Auto changes.

## License

MIT

## Support

For issues and feature requests, please use the [GitHub issue tracker](https://github.com/fmaceachen/cordova-plugin-auto/issues).
