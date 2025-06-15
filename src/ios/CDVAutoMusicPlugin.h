#import <Cordova/CDVPlugin.h>
#import <CarPlay/CarPlay.h>
#import "CDVCarPlayManager.h"

FOUNDATION_EXPORT NSString * const CDVViewControllerIsReadyNotification;

@interface CDVAutoMusicPlugin : CDVPlugin

+ (nullable CDVAutoMusicPlugin *)sharedInstance;

@property (nonatomic, strong) CDVCarPlayManager *carPlayManager;

// Connection status
- (void)isConnected:(CDVInvokedUrlCommand*)command;
- (void)registerAutoConnectListener:(CDVInvokedUrlCommand*)command;
- (void)unregisterAutoConnectListener:(CDVInvokedUrlCommand*)command;

// Playback control
- (void)play:(CDVInvokedUrlCommand*)command;
- (void)pause:(CDVInvokedUrlCommand*)command;
- (void)skipToNext:(CDVInvokedUrlCommand*)command;
- (void)skipToPrevious:(CDVInvokedUrlCommand*)command;
- (void)seekTo:(CDVInvokedUrlCommand*)command;
- (void)getPosition:(CDVInvokedUrlCommand*)command;
- (void)getCurrentPlaybackState:(CDVInvokedUrlCommand*)command;

// Queue management
- (void)updateQueue:(CDVInvokedUrlCommand*)command;
- (void)notifyQueueStorageUpdated:(CDVInvokedUrlCommand*)command;
- (void)notifyCurrentTrackUpdated:(CDVInvokedUrlCommand*)command;

// Hardcoded content (for CarPlay)
- (void)getHardcodedPlaylists:(CDVInvokedUrlCommand*)command;
- (void)getHardcodedPlaylistTracks:(CDVInvokedUrlCommand*)command;
- (void)playHardcodedTrack:(CDVInvokedUrlCommand*)command;

// Logging
- (void)getLogs:(CDVInvokedUrlCommand*)command;
- (void)clearLogs:(CDVInvokedUrlCommand*)command;
- (void)addLog:(CDVInvokedUrlCommand*)command;

@end
