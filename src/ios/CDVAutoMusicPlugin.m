#import "CDVAutoMusicPlugin.h"
#import "CDVCarPlayManager.h"
#import "CDVLogger.h"

NSString * const CDVViewControllerIsReadyNotification = @"CDVViewControllerIsReadyNotification";

static CDVAutoMusicPlugin *gSharedInstance = nil;
#import "CDVPlaylistProvider.h"

@implementation CDVAutoMusicPlugin {
    NSString *connectionCallbackId;
    NSString *mediaUpdateCallbackId;
    NSString *playbackStateCallbackId;
    NSString *queueUpdateCallbackId;
    NSString *seekCallbackId;
    NSString *customActionCallbackId;
}

+ (CDVAutoMusicPlugin *)sharedInstance {
    return gSharedInstance;
}

- (void)pluginInitialize {
    [super pluginInitialize];
    NSLog(@"CDVAutoMusicPlugin: pluginInitialize called.");
    gSharedInstance = self;
    self.carPlayManager = [[CDVCarPlayManager alloc] initWithPlugin:self];
    NSLog(@"CDVAutoMusicPlugin: CarPlayManager initialized: %@", self.carPlayManager);
    
    // Register for CarPlay connection notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(carPlayConnectionChanged:) 
                                                 name:@"CDVCarPlayConnectionChanged" 
                                               object:nil];
    
    // Register for media playback notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(mediaTrackChanged:) 
                                                 name:@"CDVMediaTrackChanged" 
                                               object:nil];
    
    // Register for playbackStateChanged notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(playbackStateChanged:) 
                                                 name:@"CDVPlaybackStateChanged" 
                                               object:nil];

    if (self.viewController) {
        NSLog(@"CDVAutoMusicPlugin: Posting CDVViewControllerIsReadyNotification. ViewController: %@, Plugin: %@", self.viewController, self);
        [[NSNotificationCenter defaultCenter] postNotificationName:CDVViewControllerIsReadyNotification object:self.viewController userInfo:@{@"plugin": self}];
    } else {
        NSLog(@"CDVAutoMusicPlugin WARN: self.viewController is nil at the end of pluginInitialize. Notification not posted immediately.");
    }
}

- (void)onReset {
    [super onReset];
}

- (void)onAppTerminate {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.carPlayManager && self.carPlayManager.musicPlayer) {
        [self.carPlayManager.musicPlayer cleanup];
    }
    [super onAppTerminate];
}

#pragma mark - Connection Methods

- (void)isConnected:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                          messageAsBool:[self.carPlayManager isConnected]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)registerAutoConnectListener:(CDVInvokedUrlCommand*)command {
    connectionCallbackId = command.callbackId;
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unregisterAutoConnectListener:(CDVInvokedUrlCommand*)command {
    connectionCallbackId = nil;
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Playback Control Methods

- (void)play:(CDVInvokedUrlCommand*)command {
    [self.carPlayManager.musicPlayer play];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)pause:(CDVInvokedUrlCommand*)command {
    [self.carPlayManager.musicPlayer pause];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)skipToNext:(CDVInvokedUrlCommand*)command {
    [self.carPlayManager.musicPlayer skipToNext];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)skipToPrevious:(CDVInvokedUrlCommand*)command {
    [self.carPlayManager.musicPlayer skipToPrevious];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)seekTo:(CDVInvokedUrlCommand*)command {
    NSNumber* position = [command.arguments objectAtIndex:0];
    [self.carPlayManager.musicPlayer seekToPosition:[position doubleValue]];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getPosition:(CDVInvokedUrlCommand*)command {
    double position = [self.carPlayManager.musicPlayer currentPlaybackPosition];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                       messageAsDouble:position];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getCurrentPlaybackState:(CDVInvokedUrlCommand*)command {
    NSString *state = [self.carPlayManager.musicPlayer currentPlaybackState];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                        messageAsString:state];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Queue Management Methods

- (void)updateQueue:(CDVInvokedUrlCommand*)command {
    NSArray* queue = [command.arguments objectAtIndex:0];
    [self.carPlayManager.musicPlayer updateQueue:queue];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)notifyQueueStorageUpdated:(CDVInvokedUrlCommand*)command {
    [self.carPlayManager.musicPlayer reloadQueue];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)notifyCurrentTrackUpdated:(CDVInvokedUrlCommand*)command {
    [self.carPlayManager.musicPlayer updateCurrentTrack];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Notification Handlers

- (void)carPlayConnectionChanged:(NSNotification*)notification {
    if (connectionCallbackId) {
        BOOL isConnected = [notification.userInfo[@"connected"] boolValue];
        
        NSDictionary* eventData = @{@"connected": @(isConnected)};
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                      messageAsDictionary:eventData];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:connectionCallbackId];
    }
}

- (void)mediaTrackChanged:(NSNotification*)notification {
    if (mediaUpdateCallbackId) {
        NSDictionary* track = notification.userInfo[@"track"];
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                      messageAsDictionary:track];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:mediaUpdateCallbackId];
    }
}

- (void)playbackStateChanged:(NSNotification*)notification {
    if (playbackStateCallbackId) {
        NSString* state = notification.userInfo[@"state"];
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                          messageAsString:state];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:playbackStateCallbackId];
    }
}

#pragma mark - Hardcoded Content Methods

- (void)getHardcodedPlaylists:(CDVInvokedUrlCommand*)command {
    NSMutableArray *playlists = [NSMutableArray array];
    
    // Create three hardcoded playlists matching the ones in Android implementation
    NSDictionary *playlist1 = @{
        @"id": @"hardcoded_playlist_1",
        @"name": @"Featured Tracks",
        @"description": @"Our featured music collection"
    };
    [playlists addObject:playlist1];
    
    NSDictionary *playlist2 = @{
        @"id": @"hardcoded_playlist_2",
        @"name": @"Sample Music",
        @"description": @"Sample tracks for demonstration"
    };
    [playlists addObject:playlist2];
    
    NSDictionary *playlist3 = @{
        @"id": @"hardcoded_playlist_3",
        @"name": @"Favorites",
        @"description": @"Your favorite tracks"
    };
    [playlists addObject:playlist3];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:playlists];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getHardcodedPlaylistTracks:(CDVInvokedUrlCommand*)command {
    NSString *playlistId = [command.arguments objectAtIndex:0];
    NSMutableArray *tracks = [NSMutableArray array];
    
    // Create a sample track that matches the one in Android implementation
    NSDictionary *track = @{
        @"id": [NSString stringWithFormat:@"%@_track_1", playlistId],
        @"title": @"SoundHelix Song 1",
        @"artist": @"T. Schürger",
        @"album": @"SoundHelix Samples",
        @"url": @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
        @"duration": @372000 // Approximate duration in ms
    };
    [tracks addObject:track];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:tracks];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)playHardcodedTrack:(CDVInvokedUrlCommand*)command {
    NSString *trackUrl = [command.arguments objectAtIndex:0];
    NSDictionary *metadata = [command.arguments objectAtIndex:1];
    
    // Create a track with the provided metadata
    NSDictionary *track = @{
        @"id": @"hardcoded_track",
        @"title": metadata[@"title"] ?: @"Unknown Title",
        @"artist": metadata[@"artist"] ?: @"Unknown Artist",
        @"album": metadata[@"album"] ?: @"Unknown Album",
        @"url": trackUrl
    };
    
    // Play the track using the CarPlay manager
    [self.carPlayManager.musicPlayer playTrack:track];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:@"Playing hardcoded track"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Logging

- (void)getLogs:(CDVInvokedUrlCommand*)command {
    NSArray *logs = [CDVLogger getLogs];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:logs];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)clearLogs:(CDVInvokedUrlCommand*)command {
    [CDVLogger clearLogs];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)addLog:(CDVInvokedUrlCommand*)command {
    NSString *message = [command argumentAtIndex:0];
    if (message) {
        [CDVLogger log:message];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    } else {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Log message is required"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

@end
