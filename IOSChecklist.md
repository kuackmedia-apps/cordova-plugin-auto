# iOS CarPlay - App Store Review Checklist

## Overview
This document outlines the requirements and considerations for publishing an iOS app with CarPlay support to pass Apple's App Store Connect review.

---

## 1. Apple Entitlement Requirements

### CarPlay Entitlement
- **Required**: You MUST request the CarPlay entitlement from Apple
- **How to Request**:
  1. Go to Apple Developer Portal
  2. Navigate to Certificates, Identifiers & Profiles
  3. Select your App ID
  4. Request the "CarPlay" entitlement
  5. Provide justification for CarPlay usage
- **Note**: This is NOT automatically available - Apple reviews each request

### Allowed App Categories
CarPlay is only available for specific app types:
- ✅ **Audio apps** (Music, Podcasts, Audiobooks, Radio)
- ✅ Navigation apps
- ✅ Messaging apps
- ✅ VoIP/Communication apps
- ✅ EV Charging apps
- ✅ Parking apps
- ✅ Quick Food Ordering apps
- ❌ Video apps, games, or other categories are NOT allowed

**Your music streaming app qualifies as an Audio app.**

---

## 2. Offline Support Requirements

### Is Offline Support Mandatory?
**NO** - Offline support is NOT mandatory for audio streaming apps.

### What Apple Expects:
- **Graceful Error Handling**: Your app must handle network issues elegantly
- **Clear User Communication**: Show appropriate error messages when offline
- **No App Crashes**: App should never crash due to lack of connectivity
- **Partial Functionality**: Basic UI navigation should still work offline

### Recommended Approach:
```javascript
// Example: Graceful offline handling
if (!navigator.onLine) {
    // Show error message in CarPlay UI
    displayCarPlayError('No internet connection. Please connect to stream music.');
    // Disable playback controls
    disablePlaybackControls();
    // Still allow browsing of cached metadata if available
    showCachedContent();
}
```

---

## 3. Technical Requirements

### Required CarPlay Features

#### 1. Native CarPlay Templates
- ✅ Use Apple's native CarPlay templates (not custom UI)
- ✅ Supported templates for audio apps:
  - `CPListTemplate` - For browsing content
  - `CPNowPlayingTemplate` - For playback control
  - `CPSearchTemplate` - For search functionality
  - `CPTabBarTemplate` - For navigation between sections

#### 2. Now Playing Integration
- ✅ Implement `MPNowPlayingInfoCenter` properly
- ✅ Update metadata in real-time:
  - Track title
  - Artist name
  - Album art
  - Duration
  - Elapsed time
- ✅ Support Remote Control Events (play, pause, next, previous)

#### 3. Audio Session Management
- ✅ Configure `AVAudioSession` correctly
- ✅ Handle interruptions (phone calls, navigation instructions)
- ✅ Resume playback after interruptions when appropriate

#### 4. User Interface Guidelines
- ✅ Simple, distraction-free UI
- ✅ Large, easy-to-tap buttons
- ✅ High contrast text and icons
- ✅ No scrolling lists longer than reasonable
- ✅ No videos or animated content

---

## 4. Critical Test Cases

### Test Cases Apple Will Review:

#### Network Connectivity
- [ ] App launches successfully with internet connection
- [ ] App launches successfully WITHOUT internet connection
- [ ] Playback starts correctly with connection
- [ ] Error message displays when trying to play without connection
- [ ] App recovers gracefully when connection is restored
- [ ] App handles connection loss during playback

#### Playback Controls
- [ ] Play button starts playback
- [ ] Pause button pauses playback
- [ ] Skip forward/backward work correctly
- [ ] Seek functionality works (if implemented)
- [ ] Volume controls work
- [ ] Playback continues when switching apps

#### Metadata Display
- [ ] Track title displays correctly
- [ ] Artist name displays correctly
- [ ] Album art loads and displays
- [ ] Playback progress updates in real-time
- [ ] Now Playing info matches actual playback

#### Browse & Search
- [ ] Content lists load correctly
- [ ] Selecting items works as expected
- [ ] Search returns relevant results
- [ ] Browsing through categories works smoothly
- [ ] No excessively deep navigation hierarchies

#### Error Handling
- [ ] No crashes on network errors
- [ ] No crashes on playback errors
- [ ] Clear error messages for common failures
- [ ] App remains stable during errors
- [ ] User can recover from errors without restarting

#### Audio Session
- [ ] Playback resumes after phone call
- [ ] Audio ducks during navigation instructions
- [ ] Works correctly with other audio sources
- [ ] Handles Bluetooth disconnection gracefully

---

## 5. Common Rejection Reasons

### Why Apps Get Rejected:

1. **Custom UI Instead of Native Templates**
   - ❌ Implementing custom CarPlay interface
   - ✅ Use Apple's provided templates only

2. **Poor Error Handling**
   - ❌ App crashes when offline
   - ❌ No error messages shown to user
   - ✅ Graceful degradation with clear messaging

3. **Incomplete Now Playing Implementation**
   - ❌ Missing metadata
   - ❌ Album art not displaying
   - ❌ Progress not updating
   - ✅ Complete MPNowPlayingInfoCenter implementation

4. **Distraction Issues**
   - ❌ Too much text on screen
   - ❌ Complex navigation flows
   - ❌ Small tap targets
   - ✅ Simple, driver-focused interface

5. **Missing Entitlement**
   - ❌ Submitting without CarPlay entitlement approval
   - ✅ Request entitlement before submission

6. **Audio Session Issues**
   - ❌ Not handling interruptions
   - ❌ Not resuming after phone calls
   - ✅ Proper AVAudioSession configuration

---

## 6. Implementation Checklist

### Before Submission:

#### Documentation
- [ ] CarPlay entitlement requested and approved
- [ ] App description mentions CarPlay support
- [ ] Screenshots include CarPlay interface (optional but recommended)

#### Code Implementation
- [ ] Native CarPlay templates implemented
- [ ] MPNowPlayingInfoCenter fully configured
- [ ] AVAudioSession properly set up
- [ ] Remote control events handled
- [ ] Error handling implemented for all network operations
- [ ] Graceful offline behavior implemented

#### Testing
- [ ] Tested on actual CarPlay-enabled vehicle OR CarPlay simulator
- [ ] All test cases from Section 4 passed
- [ ] No crashes or hangs observed
- [ ] Performance is smooth and responsive

#### User Experience
- [ ] Navigation is simple and intuitive
- [ ] Tap targets are large enough
- [ ] Text is readable at a glance
- [ ] Error messages are clear and actionable
- [ ] No videos or distracting animations

---

## 7. CarPlay-Specific Code Examples

### Handling Network Errors in CarPlay

```javascript
// Check connectivity before attempting playback
function playTrackInCarPlay(trackId) {
    if (!isNetworkAvailable()) {
        showCarPlayAlert({
            title: 'No Connection',
            message: 'Internet connection required to stream music.',
            actions: ['OK']
        });
        return;
    }

    // Proceed with playback
    startPlayback(trackId).catch(error => {
        showCarPlayAlert({
            title: 'Playback Error',
            message: 'Unable to play this track. Please try again.',
            actions: ['Retry', 'Cancel']
        });
    });
}
```

### Updating Now Playing Info

```javascript
// Update metadata when track changes
function updateNowPlayingInfo(track) {
    if (!track) return;

    const nowPlayingInfo = {
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'artwork': track.albumArt,
        'duration': track.duration,
        'elapsedPlaybackTime': track.currentTime,
        'playbackRate': track.isPlaying ? 1.0 : 0.0
    };

    // Send to native layer via Cordova plugin
    cordova.exec(
        null,
        null,
        'CarPlay',
        'updateNowPlayingInfo',
        [nowPlayingInfo]
    );
}
```

### Handling Audio Interruptions

```javascript
// Resume playback after interruption (phone call, Siri, etc.)
document.addEventListener('audiointerruptionended', function() {
    // Check if we were playing before interruption
    if (wasPlayingBeforeInterruption) {
        // Resume playback
        player.play();
        updateNowPlayingInfo(currentTrack);
    }
});

document.addEventListener('audiointerruptionbegan', function() {
    // Store playback state
    wasPlayingBeforeInterruption = player.isPlaying();
    // Pause playback
    player.pause();
});
```

---

## 8. Recommended Testing Workflow

### Phase 1: Simulator Testing
1. Use Xcode's CarPlay simulator
2. Test all basic functionality
3. Verify UI templates display correctly
4. Check metadata updates

### Phase 2: Real Device Testing
1. Test with iPhone connected to CarPlay-enabled vehicle OR
2. Use CarPlay dongle/head unit for testing
3. Test in various network conditions:
   - Strong WiFi/LTE
   - Weak signal
   - No connection
   - Connection dropping during playback

### Phase 3: Edge Case Testing
1. Test audio interruptions (phone calls)
2. Test with navigation apps running
3. Test Bluetooth disconnection
4. Test rapid track changes
5. Test search with no results
6. Test long playback sessions

---

## 9. Additional Resources

### Apple Documentation
- [CarPlay Audio App Programming Guide](https://developer.apple.com/carplay/documentation/)
- [MPNowPlayingInfoCenter Reference](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [AVAudioSession Programming Guide](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/)

### Entitlement Request
- [Request CarPlay Entitlement](https://developer.apple.com/contact/request/carplay-audio/)

---

## 10. Pre-Submission Checklist

### Final Verification Before App Store Submission:

- [ ] **Entitlement**: CarPlay entitlement approved by Apple
- [ ] **Build Configuration**: CarPlay capabilities enabled in Xcode
- [ ] **Info.plist**: UIBackgroundModes includes 'audio'
- [ ] **Testing**: All test cases passed on real CarPlay system
- [ ] **Error Handling**: Graceful behavior in all offline scenarios
- [ ] **Performance**: No lag, crashes, or hangs observed
- [ ] **Metadata**: Now Playing info always accurate
- [ ] **UI Compliance**: Only native templates used
- [ ] **Audio Session**: Interruptions handled correctly
- [ ] **Documentation**: App Store description mentions CarPlay

---

## Notes

### Offline Support Recommendation
While offline support is NOT mandatory, consider implementing basic offline features for better user experience:
- Cache recently played tracks
- Show downloaded/cached content when offline
- Allow playback of cached content
- Sync playback history when connection returns

This improves user satisfaction but is NOT required for App Store approval.

### Timeline
- **Entitlement request**: Can take 1-2 weeks for Apple to approve
- **Review process**: Standard App Store review timeframes (1-3 days typically)
- **Resubmission**: If rejected, address issues and resubmit

---

**Last Updated**: 2025-11-18
**Version**: 1.0
