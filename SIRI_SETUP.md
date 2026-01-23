# Quick Setup: Enabling Siri for CarPlay Music












































































































































echo ""fi    echo "- Download fresh provisioning profile"    echo "- Verify Siri entitlement is enabled in Apple Developer Portal"    echo "- Check plugin.xml has all Siri configurations"    echo "If issues persist:"    echo ""    echo "4. Run this script again"    echo "3. Run: cordova build ios"    echo "2. Run: cordova platform add ios"    echo "1. Run: cordova platform remove ios"    echo "To fix:"    echo ""    echo "❌ Found $errors issue(s)"else    echo "6. Build and test: 'Hey Siri, play music on [your app]'"    echo "5. Make sure provisioning profile has Siri entitlement"    echo "4. If missing, add it manually with + Capability"    echo "3. Verify 'Siri' capability is present"    echo "2. Go to Signing & Capabilities"    echo "1. Open in Xcode: platforms/ios/*.xcworkspace"    echo "Next steps:"    echo ""    echo "✅ Configuration looks good!"if [ $errors -eq 0 ]; thenecho "=========================================="echo ""fi    echo "  ⚠️  No entitlements file found (will be created by Xcode)"else    fi        ((errors++))        echo "  ⚠️  CarPlay entitlement NOT in file"    else        echo "  ✅ CarPlay entitlement present"    if grep -q "com.apple.developer.carplay-audio" "$ENTITLEMENTS"; then        fi        ((errors++))        echo "  ⚠️  Siri entitlement NOT in file (you may need to add manually in Xcode)"    else        echo "  ✅ Siri entitlement present"    if grep -q "com.apple.developer.siri" "$ENTITLEMENTS"; then        echo "  📄 Found: $ENTITLEMENTS"if [ -n "$ENTITLEMENTS" ]; thenENTITLEMENTS=$(find $IOS_PATH -name "*.entitlements" | head -1)echo "✓ Checking Entitlements..."# Check entitlements fileecho ""fi    ((errors++))    echo "  ❌ Audio background mode NOT enabled"else    echo "  ✅ Audio background mode enabled"if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null | grep -q "audio"; thenecho "✓ Checking Background Modes..."# Check for audio background modeecho ""fi    ((errors++))    echo "  ❌ INPlayMediaIntent NOT in user activity types"else    echo "  ✅ INPlayMediaIntent found in user activity types"if /usr/libexec/PlistBuddy -c "Print :NSUserActivityTypes:0" "$PLIST" 2>/dev/null | grep -q "INPlayMediaIntent"; thenfi    ((errors++))    echo "  ❌ INPlayMediaIntent NOT in supported intents"else    echo "  ✅ INPlayMediaIntent found in supported intents"if /usr/libexec/PlistBuddy -c "Print :INIntentsSupported:0" "$PLIST" 2>/dev/null | grep -q "INPlayMediaIntent"; thenecho "✓ Checking INPlayMediaIntent support..."# Check for INPlayMediaIntent specificallyecho ""check_key "UISceneConfigurations" "CarPlay Scene Configuration" || ((errors++))# Check CarPlaycheck_key "UIBackgroundModes" "Background Modes (audio)" || ((errors++))check_key "NSUserActivityTypes" "User Activity Types" || ((errors++))check_key "INIntentsSupported" "Intents Supported" || ((errors++))check_key "NSSiriUsageDescription" "Siri Usage Description" || ((errors++))# Check Siri keyserrors=0}    fi        return 1        echo "  ❌ $description: MISSING"    else        return 0        echo "  ✅ $description: Found"        value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null)    if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" &>/dev/null; then        local description=$2    local key=$1check_key() {# Function to check plist keyecho "✓ Checking required Info.plist keys..."# Check for required keysecho ""echo "📄 Checking: $PLIST"fi    exit 1    echo "❌ Info.plist not found. Build the app first."if [ -z "$PLIST" ]; thenPLIST=$(find $IOS_PATH -name "*-Info.plist" | grep -v CordovaLib | head -1)# Find Info.plistfi    exit 1    echo "❌ iOS platform not found. Run 'cordova build ios' first."if [ ! -d "$IOS_PATH" ]; thenIOS_PATH="platforms/ios"# Find the app bundleecho ""echo "=========================================="echo "🔍 Checking Siri + CarPlay Configuration..."# Run this after building your iOS app to verify Siri is properly configured# Siri + CarPlay Configuration Checker## What Was Changed

✅ Added Siri entitlement configuration to `plugin.xml`  
✅ Added `INIntentsRestrictionsKey` to map intents to handler  
✅ Created AppDelegate hook to handle Siri intents  
✅ Extended `CDVAutoMusicPlugin` with Siri intent handling  
✅ Added JavaScript API `onSiriIntent()` for listening to Siri commands  
✅ Updated TypeScript definitions  

## What You Need To Do

### 1. Enable Siri in Apple Developer Portal
1. Go to https://developer.apple.com
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select your App ID
4. Click **Edit**
5. Enable **Siri** capability
6. Save changes
7. **Download new provisioning profile**
8. Install the new profile in Xcode

### 2. Rebuild Your Cordova App
```bash
# Remove old platform
cordova platform remove ios

# Add fresh platform
cordova platform add ios

# Build
cordova build ios

# Check configuration (optional but recommended)
./check-siri-config.sh
```

The diagnostic script will verify all required Info.plist keys are present.

### 3. Verify in Xcode
1. Open `platforms/ios/YourApp.xcworkspace`
2. Select your target
3. Go to **Signing & Capabilities**
4. Verify **Siri** capability is present
5. If not, click **+ Capability** and add **Siri**

### 4. Add JavaScript Listener
In your Cordova app:

```javascript
document.addEventListener('deviceready', function() {
    // Listen for Siri intents
    cordova.plugins.auto.onSiriIntent(function(data) {
        console.log('Siri wants to play:', data);
        
        // data.artistName - e.g., "Shakira"
        // data.mediaName - e.g., "Shakira" or "Waka Waka"
        // data.albumName - e.g., "El Dorado"
        // data.isCarPlayConnected - true if in CarPlay
        
        // Search your music catalog and play
        searchAndPlay(data);
    });
});

async function searchAndPlay(intentData) {
    // 1. Search your music catalog
    const results = await fetch('/api/search?artist=' + intentData.artistName);
    const tracks = await results.json();
    
    // 2. Update the queue
    cordova.plugins.auto.updateQueue(tracks);
    
    // 3. Set current track
    cordova.plugins.auto.notifyCurrentTrackUpdated();
    
    // 4. CRITICAL FOR CARPLAY: Start playback
    cordova.plugins.auto.playSiriSearchResults(
        () => console.log('Playing in CarPlay'),
        (err) => console.error('Error:', err)
    );
}
```

**IMPORTANT**: You MUST call `playSiriSearchResults()` after updating the queue, otherwise it won't play in CarPlay!

### 5. Test
1. Deploy to a **real iOS device** (not simulator)
2. Make sure Siri is enabled: Settings → Siri & Search → Your App
3. Say: **"Hey Siri, play Shakira on [Your App Name]"**
4. Your callback should receive the intent data
5. Your app should search and play the music

## Common Issues

### "App does not allow Siri" or "[App] does not allow to do that"
This is a configuration issue. Check ALL of these:

1. **Siri entitlement in provisioning profile**
   - Go to Apple Developer Portal → Certificates, Identifiers & Profiles
   - Select your App ID
   - Verify **Siri** is enabled (checkbox checked)
   - Download NEW provisioning profile
   - In Xcode: Select target → Signing & Capabilities → Download Manual Profiles

2. **Both CarPlay AND Siri entitlements approved**
   - Both must be approved by Apple
   - Check your Apple Developer account for approval status

3. **Info.plist has all keys** (after building):
   ```bash
   # Navigate to your built app
   cd platforms/ios/YourApp
   
   # Check for required keys:
   /usr/libexec/PlistBuddy -c "Print :INIntentsSupported" YourApp-Info.plist
   /usr/libexec/PlistBuddy -c "Print :NSUserActivityTypes" YourApp-Info.plist
   /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" YourApp-Info.plist
   ```
   All should return arrays with the proper values

4. **Xcode capabilities**:
   - Open `platforms/ios/YourApp.xcworkspace` in Xcode
   - Select your app target
   - Go to **Signing & Capabilities** tab
   - You MUST see: **Siri**, **CarPlay**, **Background Modes**
   - If missing, click **+ Capability** and add them manually

5. **iOS Settings**:
   - Settings → Siri & Search → Your App
   - Enable **"Use with Ask Siri"**
   - Enable **"Show Siri Suggestions"**

6. **Clean rebuild**:
   ```bash
   cordova platform remove ios
   cordova platform add ios
   cordova prepare ios
   cordova build ios
   ```
   Then open in Xcode and run from there to see console logs

### Callback never fires
- **Cause**: Listener not registered or AppDelegate not modified
- **Fix**: Rebuild platform and check `AppDelegate.m`/`AppDelegate.swift` contains Siri handling code

### Works on phone but NOT in CarPlay
- **Cause**: Not calling `playSiriSearchResults()` after updating queue
- **Fix**: Always call `cordova.plugins.auto.playSiriSearchResults()` after search
- This method triggers playback specifically for CarPlay's audio route

### Xcode shows "Siri" as missing
- **Cause**: Entitlements not applied
- **Fix**: Manually add Siri capability in Xcode project settings

## Debugging

Enable verbose logging by running from Xcode. Look for:
- `🎤 [SiriIntentHandler]` - Intent handler logs
- `🎤 [AppDelegate]` - App delegate logs  
- `🎤 [AutoMusicPlugin]` - Plugin logs

## Files Modified

- `plugin.xml` - Added Siri entitlements and Info.plist entries
- `hooks/add_siri_appdelegate.js` - New hook to modify AppDelegate
- `src/ios/CDVAutoMusicPlugin.swift` - Added Siri intent handling
- `www/myplugin.js` - Added `onSiriIntent()` method
- `types/index.d.ts` - Added TypeScript definitions

## Next Steps

Read [SIRI_INTEGRATION.md](SIRI_INTEGRATION.md) for detailed implementation guide.
