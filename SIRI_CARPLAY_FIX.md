# Siri + CarPlay Quick Reference

## The Problem
✅ Siri works on phone  
❌ Siri doesn't work in CarPlay

## The Solution

After your Siri search completes, you MUST call:

```javascript
cordova.plugins.auto.playSiriSearchResults();
```

## Complete Flow

```javascript
// 1. Register listener (once, on app start)
cordova.plugins.auto.onSiriIntent(handleSiri);

// 2. Handle the intent
async function handleSiri(data) {
    // Search your catalog
    const tracks = await searchMusic(data.artistName || data.mediaName);
    
    // Update queue
    cordova.plugins.auto.updateQueue(tracks);
    
    // Set current track
    cordova.plugins.auto.notifyCurrentTrackUpdated();
    
    // ⚠️ CRITICAL: Start CarPlay playback
    cordova.plugins.auto.playSiriSearchResults();
}
```

## Why?

When Siri is triggered in CarPlay:
- The search happens ✅
- The queue updates ✅
- But playback needs to be explicitly started in CarPlay ❌

The `playSiriSearchResults()` method:
1. Reloads the queue in the CarPlay player
2. Starts playback on the CarPlay audio route
3. Updates the car's Now Playing display

## Test It

1. **Rebuild the app completely**:
   ```bash
   cordova platform remove ios
   cordova platform add ios
   cordova build ios
   ```

2. **Verify in Xcode**:
   - Open `platforms/ios/YourApp.xcworkspace`
   - Check Info.plist contains:
     - `INIntentsSupported` array with `INPlayMediaIntent`
     - `NSUserActivityTypes` array with `INPlayMediaIntent`
     - `UIBackgroundModes` with `audio`
     - `NSSiriUsageDescription`
   - Check Signing & Capabilities has both **Siri** and **CarPlay** enabled

3. **Connect iPhone to CarPlay**

4. **Test Siri**:
   - Say: **"Hey Siri, play music on Brisamusic"**
   - Or: **"Hey Siri, play [artist] on Brisamusic"**

5. **Check logs in Xcode console** for 🎤 emoji markers

## If You Get "Brisamusic does not allow to do that"

This error means iOS doesn't recognize your app can handle the intent. Check:

1. **Siri entitlement is in provisioning profile**
   - Go to Apple Developer Portal
   - Download fresh provisioning profile with Siri enabled
   - Install in Xcode

2. **Info.plist has all required keys**
   ```bash
   # After building, check the Info.plist:
   cd platforms/ios/YourApp
   cat YourApp-Info.plist | grep -A 2 "INIntentsSupported"
   ```
   Should show `INPlayMediaIntent`

3. **App is running in background audio mode**
   - Settings → Siri & Search → Brisamusic → Enable "Use with Ask Siri"
   
4. **CarPlay entitlement is active**
   - Both CarPlay AND Siri entitlements must be approved by Apple

5. **Clean rebuild**:
   ```bash
   cordova platform remove ios
   cordova platform add ios
   cordova prepare ios
   cordova build ios
   ```

6. **Check Xcode capabilities**:
   - Open project in Xcode
   - Select target → Signing & Capabilities
   - Should see: **Siri**, **CarPlay**, **Background Modes (Audio)**

## Debug Checklist

- [ ] Siri entitlement enabled in Apple Developer Portal
- [ ] `onSiriIntent()` registered on app start
- [ ] Callback receives data when Siri triggered
- [ ] Queue updated with search results
- [ ] **`playSiriSearchResults()` called after queue update** ← Most common miss!
- [ ] Check Xcode console for 🎤 emoji logs

## API Reference

### Register Listener
```javascript
cordova.plugins.auto.onSiriIntent(function(data) {
    // data.artistName, data.mediaName, data.albumName
    // data.isCarPlayConnected - true if in CarPlay
});
```

### Trigger Playback
```javascript
cordova.plugins.auto.playSiriSearchResults(
    successCallback,  // optional
    errorCallback     // optional
);
```

## Full Example

```javascript
document.addEventListener('deviceready', function() {
    // Setup Siri handler
    cordova.plugins.auto.onSiriIntent(async function(intent) {
        try {
            // Search
            const response = await fetch(
                `/api/search?q=${intent.artistName || intent.mediaName}`
            );
            const data = await response.json();
            
            // Update queue
            cordova.plugins.auto.updateQueue(data.tracks);
            cordova.plugins.auto.notifyCurrentTrackUpdated();
            
            // Start CarPlay playback
            cordova.plugins.auto.playSiriSearchResults(
                () => console.log('✅ Playing in CarPlay'),
                (err) => console.error('❌ Error:', err)
            );
        } catch (err) {
            console.error('Search failed:', err);
        }
    });
});
```

---

📖 For detailed documentation, see [SIRI_INTEGRATION.md](SIRI_INTEGRATION.md)
