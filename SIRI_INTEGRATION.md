# Siri Integration Guide for CarPlay Music Plugin

This guide explains how to enable and use Siri voice commands with your CarPlay music app.

## Prerequisites

### 1. Apple Developer Account Requirements
- **Siri Entitlement**: Your app must have the Siri capability enabled
- **CarPlay Entitlement**: Required for CarPlay audio apps (already configured)
- Both entitlements must be added to your provisioning profile

### 2. Request Siri Entitlement
1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to your App ID
3. Enable **Siri** capability
4. Regenerate and download your provisioning profile
5. Update your Xcode project with the new profile

## What's Been Added

The plugin now includes:

### 1. Info.plist Entries
- `NSSiriUsageDescription`: Explains why your app needs Siri
- `NSUserActivityTypes`: Declares support for `INPlayMediaIntent`
- `INIntentsSupported`: Lists supported intent types
- `INIntentsRestrictionsKey`: Maps intent classes to handler classes

### 2. Entitlements
- `com.apple.developer.siri`: Enables Siri capability

### 3. Swift Components
- **CDVSiriIntentHandler**: Handles incoming Siri intents
- **CDVAutoMusicPlugin**: Extended to process Siri search requests
- **AppDelegate Hook**: Automatically adds intent handling to your app

## How to Use

### 1. Register a Siri Intent Listener

In your Cordova app's JavaScript code:

```javascript
// Register listener for Siri intents
cordova.plugins.auto.onSiriIntent(function(intentData) {
    console.log('Siri intent received:', intentData);
    
    // intentData contains:
    // {
    //   mediaName: "Shakira",           // Artist, song, or album name
    //   artistName: "Shakira",          // Specific artist name
    //   albumName: "El Dorado",         // Specific album name
    //   mediaType: 1,                   // 1=Music, 2=Podcast, etc.
    //   isCarPlayConnected: true        // Whether CarPlay is active
    // }
    
    // Perform search in your music catalog
    searchAndPlay(intentData);
});

async function searchAndPlay(intentData) {
    console.log('Searching for:', intentData.artistName || intentData.mediaName);
    
    try {
        // 1. Search your music API
        const results = await searchMusicCatalog(intentData);
        
        // 2. Update the queue with search results
        cordova.plugins.auto.updateQueue(results.tracks);
        
        // 3. Set current track (first result)
        cordova.plugins.auto.notifyCurrentTrackUpdated();
        
        // 4. CRITICAL: Trigger playback in CarPlay
        cordova.plugins.auto.playSiriSearchResults(
            function() {
                console.log('✅ Playing Siri results in CarPlay');
            },
            function(err) {
                console.error('❌ Failed to play:', err);
            }
        );
        
    } catch (error) {
        console.error('Search failed:', error);
    }
}

async function searchMusicCatalog(intentData) {
    // Your API search logic
    if (intentData.artistName) {
        return await fetch(`/api/search/artist?q=${intentData.artistName}`);
    } else if (intentData.mediaName) {
        return await fetch(`/api/search?q=${intentData.mediaName}`);
    }
}
```

**IMPORTANT for CarPlay**: You MUST call `cordova.plugins.auto.playSiriSearchResults()` after updating the queue. This ensures playback starts in CarPlay, not just on the phone.

### 2. Test Siri Commands

Users can say:
- **"Hey Siri, play music on [Your App Name]"**
- **"Hey Siri, play Shakira on [Your App Name]"**
- **"Hey Siri, play El Dorado by Shakira on [Your App Name]"**
- **"Hey Siri, play some music on [Your App Name]"**

### 3. Handle Different Intent Types

The `intentData.mediaType` indicates what type of media was requested:

```javascript
function handleSiriIntent(intentData) {
    switch(intentData.mediaType) {
        case 1: // Music
            console.log('User wants music');
            break;
        case 2: // Podcasts
            console.log('User wants podcasts');
            break;
        case 3: // Audiobooks
            console.log('User wants audiobooks');
            break;
        default:
            console.log('Unknown media type');
    }
}
```

## Workflow

1. **User says**: "Hey Siri, play Shakira on BrisaMusic"
2. **iOS** routes the intent to your app
3. **CDVSiriIntentHandler** processes the intent
4. **AppDelegate** receives the NSUserActivity
5. **CDVAutoMusicPlugin** extracts search parameters
6. **Your JavaScript code** receives the intent data via callback
7. **Your app** searches and plays the requested music

## Troubleshooting

### "App does not allow Siri"

This error means one or more of these is missing:

1. **Siri entitlement not in provisioning profile**
   - Solution: Re-download provisioning profile with Siri enabled
   - Verify in Xcode: Project Settings → Signing & Capabilities → Should see "Siri"

2. **App not rebuilt after plugin update**
   - Solution: Remove and re-add the iOS platform:
   ```bash
   cordova platform remove ios
   cordova platform add ios
   cordova build ios
   ```

3. **Entitlements file not updated**
   - Check `platforms/ios/YourApp/YourApp.entitlements` contains:
   ```xml
   <key>com.apple.developer.siri</key>
   <true/>
   ```

### Intent Not Received

If your callback never fires:

1. **Check listener is registered early**
   ```javascript
   document.addEventListener('deviceready', function() {
       // Register immediately after device ready
       cordova.plugins.auto.onSiriIntent(handleIntent);
   });
   ```

2. **Verify AppDelegate was modified**
   - Check `platforms/ios/YourApp/Classes/AppDelegate.m` or `AppDelegate.swift`
   - Should contain `application:continueUserActivity:restorationHandler:`

3. **Enable verbose logging**
   - Run from Xcode to see console logs
   - Look for logs starting with "🎤 [AppDelegate]" or "🎤 [SiriIntentHandler]"

### Works on Phone But Not in CarPlay

This is the most common issue! The solution:

**Problem**: Siri intent triggers on the phone, but nothing plays in CarPlay.

**Solution**: You MUST call `cordova.plugins.auto.playSiriSearchResults()` after updating the queue:

```javascript
cordova.plugins.auto.onSiriIntent(async function(data) {
    // 1. Search your catalog
    const tracks = await searchMusic(data.artistName);
    
    // 2. Update queue
    cordova.plugins.auto.updateQueue(tracks);
    
    // 3. Update current track
    cordova.plugins.auto.notifyCurrentTrackUpdated();
    
    // 4. CRITICAL: Start CarPlay playback
    cordova.plugins.auto.playSiriSearchResults();
});
```

**Why this is needed**: When Siri is triggered in CarPlay, the audio must be routed through the CarPlay player instance, not just the phone's player. The `playSiriSearchResults()` method:
- Reloads the queue in CarPlay
- Starts playback on the CarPlay audio route
- Updates the Now Playing info on the car's display

**Check if CarPlay is active**:
```javascript
if (data.isCarPlayConnected) {
    console.log('User is in CarPlay mode');
    // Make sure to call playSiriSearchResults()
}
```

### Testing Tips

1. **Test on real device** - Siri intents don't work reliably in simulator
2. **Say app name clearly** - Siri needs to recognize your app name
3. **Enable Siri in Settings** - Settings → Siri & Search → Your App
4. **Check Siri permissions** - iOS may ask user to allow Siri access

## Advanced: Donating Intents

To make Siri better at predicting what users want, donate intents when users play music:

```javascript
// When user manually plays an artist
function onUserPlaysArtist(artistName) {
    // Your existing play logic
    playArtist(artistName);
    
    // iOS will learn this pattern
    // (Intent donation would need native code - future enhancement)
}
```

## Example Implementation

```javascript
class MusicSiriHandler {
    constructor() {
        this.setupSiriListener();
    }
    
    setupSiriListener() {
        if (typeof cordova === 'undefined' || cordova.platformId !== 'ios') {
            console.log('Siri only available on iOS');
            return;
        }
        
        cordova.plugins.auto.onSiriIntent(this.handleIntent.bind(this));
        console.log('Siri intent listener registered');
    }
    
    async handleIntent(intentData) {
        console.log('Processing Siri request:', intentData);
        
        try {
            let tracks = [];
            
            // Priority 1: Specific artist + album
            if (intentData.artistName && intentData.albumName) {
                tracks = await this.searchAlbum(intentData.artistName, intentData.albumName);
            }
            // Priority 2: Artist only
            else if (intentData.artistName) {
                tracks = await this.searchArtist(intentData.artistName);
            }
            // Priority 3: General media name (could be song, artist, or album)
            else if (intentData.mediaName) {
                tracks = await this.searchGeneral(intentData.mediaName);
            }
            // Priority 4: Just play something
            else {
                tracks = await this.getRecommended();
            }
            
            if (tracks && tracks.length > 0) {
                // Update the queue
                cordova.plugins.auto.updateQueue(tracks);
                
                // Set current track to first result
                cordova.plugins.auto.notifyCurrentTrackUpdated();
                
                // CRITICAL: Start playback (especially for CarPlay)
                cordova.plugins.auto.playSiriSearchResults(
                    () => console.log('✅ Playing Siri results'),
                    (err) => console.error('❌ Playback failed:', err)
                );
            } else {
                this.showError('Could not find that music');
            }
            
        } catch (error) {
            console.error('Failed to handle Siri intent:', error);
            this.showError('Could not find that music');
        }
    }
    
    async searchArtist(artistName) {
        const response = await fetch(`/api/search/artist?q=${encodeURIComponent(artistName)}`);
        const data = await response.json();
        
        if (data.artists && data.artists.length > 0) {
            const artist = data.artists[0];
            // Get artist's top tracks
            const tracksResponse = await fetch(`/api/artist/${artist.id}/tracks`);
            const tracksData = await tracksResponse.json();
            return tracksData.tracks;
        }
        return [];
    }
    
    async searchAlbum(artistName, albumName) {
        const response = await fetch(
            `/api/search/album?artist=${encodeURIComponent(artistName)}&album=${encodeURIComponent(albumName)}`
        );
        const data = await response.json();
        
        if (data.albums && data.albums.length > 0) {
            const album = data.albums[0];
            const tracksResponse = await fetch(`/api/album/${album.id}/tracks`);
            const tracksData = await tracksResponse.json();
            return tracksData.tracks;
        }
        return [];
    }
    
    async searchGeneral(query) {
        const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
        const data = await response.json();
        
        // Try to find best match: track > album > artist
        if (data.tracks && data.tracks.length > 0) {
            return [data.tracks[0]]; // Play single track
        } else if (data.albums && data.albums.length > 0) {
            return await this.searchAlbum(data.albums[0].artist, data.albums[0].name);
        } else if (data.artists && data.artists.length > 0) {
            return await this.searchArtist(data.artists[0].name);
        }
        return [];
    }
    
    async getRecommended() {
        const response = await fetch('/api/recommended');
        const data = await response.json();
        return data.tracks || [];
    }
    
    showError(message) {
        // Show error to user (CarPlay safe)
        console.error(message);
        // You could also update a status in your UI
    }
}

// Initialize
document.addEventListener('deviceready', function() {
    const siriHandler = new MusicSiriHandler();
});
```

## Next Steps

1. Rebuild your iOS app
2. Enable Siri capability in your provisioning profile
3. Test with "Hey Siri, play [artist] on [your app name]"
4. Implement search and playback logic in your app
5. Submit to App Store

## Resources

- [Apple SiriKit Documentation](https://developer.apple.com/documentation/sirikit)
- [INPlayMediaIntent Reference](https://developer.apple.com/documentation/sirikit/inplaymediaintent)
- [CarPlay Audio Apps Guide](https://developer.apple.com/carplay/documentation/)
