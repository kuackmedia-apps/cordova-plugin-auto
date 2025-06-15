#import "CDVCarPlayManager.h"
#import "CDVAutoMusicPlugin.h"
#import "CDVMusicPlayer.h"
#import "CDVPlaylistProvider.h"
#import "CDVLogger.h"

@implementation CDVCarPlayManager {
    __weak CDVAutoMusicPlugin *_plugin;
    CPTabBarTemplate *_tabBarTemplate;
    CPNowPlayingTemplate *_nowPlayingTemplate;
    CPListTemplate *_playlistsTemplate;
}

- (instancetype)initWithPlugin:(CDVAutoMusicPlugin *)plugin {
    self = [super init];
    if (self) {
        _plugin = plugin;
        _connected = NO;
        _musicPlayer = [[CDVMusicPlayer alloc] initWithManager:self];
    }
    return self;
}

- (BOOL)isConnected {
    return _connected;
}

#pragma mark - CPTemplateApplicationSceneDelegate

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController {
    // CarPlay connected
    _connected = YES;
    
    // Store the interface controller
    self.interfaceController = interfaceController;
    
    // Initialize templates
    [self setupTemplates:interfaceController];
    
    // Notify the plugin about the connection
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVCarPlayConnectionChanged" 
                                                         object:nil 
                                                       userInfo:@{@"connected": @(YES)}];
    
    // Force refresh of Now Playing info if music is already playing
    // This ensures CarPlay shows the correct track info even if it connects after playback started
    if (_musicPlayer && _musicPlayer.isPlaying) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Refresh Now Playing info with a slight delay to ensure CarPlay UI is ready
            [_musicPlayer updateNowPlayingInfoIfNeeded];
            
            // If a track is playing, make sure the Now Playing template is displayed
            if (_musicPlayer.currentTrack) {
                [self showNowPlayingTemplate:nil];
            }
        });
    }
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didDisconnectInterfaceController:(CPInterfaceController *)interfaceController {
    // CarPlay disconnected
    _connected = NO;
    
    // Notify the plugin about the disconnection
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVCarPlayConnectionChanged" 
                                                        object:nil 
                                                      userInfo:@{@"connected": @(NO)}];
}

#pragma mark - Template Setup

- (void)setupTemplates:(CPInterfaceController *)interfaceController {
    [CDVLogger log:@"CDVCarPlayManager: setupTemplates starting..."];
    
    if (!interfaceController) {
        [CDVLogger log:@"CDVCarPlayManager ERROR: interfaceController is nil in setupTemplates"];
        return;
    }
    
    // Create a root template with tabs for playlists and now playing
    [self setupRootTemplate:interfaceController];
    
    // Setup the now playing template
    [self setupNowPlayingTemplate];
    
    // Register for notification to show the now playing template
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showNowPlayingTemplate:)
                                                 name:@"CDVShowNowPlayingTemplate"
                                               object:nil];
    
    [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Templates setup completed. TabBar template: %@, Playlists template: %@, NowPlaying template: %@", 
          _tabBarTemplate, _playlistsTemplate, _nowPlayingTemplate]];
}

- (void)setupRootTemplate:(CPInterfaceController *)interfaceController {
    [CDVLogger log:@"CDVCarPlayManager: setupRootTemplate starting..."];
    
    // Create the playlists template
    _playlistsTemplate = [self createPlaylistsTemplate];
    if (!_playlistsTemplate) {
        NSLog(@"CDVCarPlayManager ERROR: Failed to create playlists template");
    } else {
        NSLog(@"CDVCarPlayManager: Playlists template created successfully with %lu sections", 
               (unsigned long)_playlistsTemplate.sections.count);
    }
    
    // Create the now playing template - but don't add it to the tab bar as it's not allowed
    _nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
    NSLog(@"CDVCarPlayManager: Now playing template obtained: %@", _nowPlayingTemplate);
    
    // Create a tab bar template with ONLY the playlists template - CPNowPlayingTemplate is not allowed in tab bars
    [CDVLogger log:@"CDVCarPlayManager: Creating tab bar with just the playlists template since CPNowPlayingTemplate is not allowed in tab bars"];
    NSArray *templates = @[_playlistsTemplate];
    _tabBarTemplate = [[CPTabBarTemplate alloc] initWithTemplates:templates];
    [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Tab bar template created with %lu templates", (unsigned long)templates.count]];
    
    // Set the root template to the interface controller
    [CDVLogger log:@"CDVCarPlayManager: Setting root template to interface controller..."];
    [interfaceController setRootTemplate:_tabBarTemplate animated:YES completion:^(BOOL success, NSError * _Nullable error) {
        if (error) {
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager ERROR: Failed to set root template: %@", error]];
        } else {
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Root template set successfully: %@", success ? @"YES" : @"NO"]];
        }
    }];
}

- (CPListTemplate *)createPlaylistsTemplate {
    [CDVLogger log:@"CDVCarPlayManager: createPlaylistsTemplate starting..."];
    
    // Create a list template for playlists
    NSMutableArray *playlistItems = [NSMutableArray array];
    
    // Get playlists from the provider
    NSArray *playlists = [CDVPlaylistProvider hardcodedPlaylists];
    [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Got %lu playlists from provider", (unsigned long)playlists.count]];
    
    if (playlists.count == 0) {
        [CDVLogger log:@"CDVCarPlayManager WARNING: No playlists returned from provider"];
    }
    
    // Create list items for each playlist
    for (NSDictionary *playlist in playlists) {
        [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Creating item for playlist: %@", playlist[@"title"]]];
        
        // Ensure required fields exist
        if (!playlist[@"title"] || !playlist[@"id"]) {
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager ERROR: Playlist missing required fields: %@", playlist]];
            continue;
        }
        
        CPListItem *item = [[CPListItem alloc] initWithText:playlist[@"title"] 
                                               detailText:playlist[@"description"]];
        
        // Set handler for when a playlist is selected
        __weak typeof(self) weakSelf = self;
        item.handler = ^(CPListItem * _Nonnull item, dispatch_block_t  _Nonnull completion) {
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Playlist selected: %@", item.text]];
            
            // Load tracks for the selected playlist
            NSArray *tracks = [CDVPlaylistProvider tracksForPlaylist:playlist[@"id"]];
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Got %lu tracks for playlist %@", (unsigned long)tracks.count, playlist[@"id"]]];
            
            if (tracks.count == 0) {
                [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager WARNING: No tracks returned for playlist %@", playlist[@"id"]]];
            }
            
            [weakSelf.musicPlayer updateQueue:tracks];
            [weakSelf.musicPlayer play];
            completion();
        };
        
        [playlistItems addObject:item];
    }
    
    [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Created %lu playlist items", (unsigned long)playlistItems.count]];
    
    // Create a section with the playlist items
    CPListSection *section = [[CPListSection alloc] initWithItems:playlistItems];
    
    // Create the list template with the section
    CPListTemplate *listTemplate = [[CPListTemplate alloc] initWithTitle:@"Playlists" sections:@[section]];
    [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Created playlist template with title 'Playlists' and %lu sections", 
          (unsigned long)listTemplate.sections.count]];
    
    return listTemplate;
}

- (void)setupNowPlayingTemplate {
    [CDVLogger log:@"CDVCarPlayManager: Setting up now playing template"];
    
    // Get the shared template - this is a singleton provided by the system
    _nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
    
    // Configure the now playing template
    _nowPlayingTemplate.albumArtistButtonEnabled = YES;
    _nowPlayingTemplate.upNextButtonEnabled = YES;
    
    // Needed for iOS 14+: make sure template is properly configured with buttons
    if (@available(iOS 14.0, *)) {
        [CDVLogger log:@"CDVCarPlayManager: Setting up now playing template with explicit button configurations"];
        
        // For newer iOS versions, the buttons are automatically configured by the system
        // No need to create or configure them manually
        [CDVLogger log:@"CDVCarPlayManager: Using system-provided Now Playing buttons in iOS 14+"];
        
        // We don't need to manually set the buttons as the system handles it
    }
    
    // Add the template as the now playing template for the music player
    [_musicPlayer setNowPlayingTemplate:_nowPlayingTemplate];
    
    // Register for notifications to handle Now Playing button taps
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(nowPlayingButtonTapped:) 
                                                 name:@"CPNowPlayingButtonTapped" 
                                               object:nil];
                                                
    // Register for notifications to update the Now Playing template
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateNowPlayingTemplate:)
                                                 name:@"CDVUpdateNowPlayingTemplate"
                                               object:nil];
    
    [CDVLogger log:@"CDVCarPlayManager: Now playing template setup complete"];
}

- (void)nowPlayingButtonTapped:(NSNotification *)notification {
    NSString *buttonType = notification.userInfo[@"buttonType"];
    if ([buttonType isEqualToString:@"playPause"]) {
        [_musicPlayer togglePlayPause];
    } else if ([buttonType isEqualToString:@"next"]) {
        [_musicPlayer nextTrack];
    } else if ([buttonType isEqualToString:@"previous"]) {
        [_musicPlayer previousTrack];
    }
}



- (void)showNowPlayingTemplate:(NSNotification *)notification {
    [CDVLogger log:@"CDVCarPlayManager: Received request to show Now Playing template"];
    
    if (!self.interfaceController) {
        [CDVLogger log:@"CDVCarPlayManager ERROR: Cannot show Now Playing template - interface controller is nil"];
        return;
    }
    
    // Prevent redundant template displays
    static BOOL isTemplateDisplayInProgress = NO;
    if (isTemplateDisplayInProgress) {
        [CDVLogger log:@"CDVCarPlayManager: Template display already in progress, skipping duplicate request"];
        return;
    }
    
    isTemplateDisplayInProgress = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Get the Now Playing template
        CPNowPlayingTemplate *nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
        
        // Check if the Now Playing template is already the top-level template
        if ([self.interfaceController.topTemplate isKindOfClass:[CPNowPlayingTemplate class]]) {
            [CDVLogger log:@"CDVCarPlayManager: Now Playing template is already displayed, skipping push"];
            isTemplateDisplayInProgress = NO;
            return;
        }
                
        // Push the Now Playing template onto the navigation stack
        [self.interfaceController pushTemplate:nowPlayingTemplate animated:YES completion:^(BOOL success, NSError * _Nullable error) {
            isTemplateDisplayInProgress = NO;
            
            if (!success) {
                [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager ERROR: Failed to push Now Playing template: %@", error]];
            } else {
                [CDVLogger log:@"CDVCarPlayManager: Now Playing template displayed successfully"];
                // Note: We cannot call presentTemplate with CPNowPlayingTemplate as it's not supported
                // CPNowPlayingTemplate can only be pushed, not presented
            }
        }];
    });
}

- (void)updateNowPlayingTemplate:(NSNotification *)notification {
    [CDVLogger log:@"CDVCarPlayManager: Received request to update Now Playing template UI"];
    NSDictionary *track = notification.userInfo[@"track"];
    NSNumber *isPlaying = notification.userInfo[@"isPlaying"];
    
    if (track) {
        [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Updating now playing template with track: %@", track[@"title"]]];
        
        // Get the Now Playing template and update it explicitly
        CPNowPlayingTemplate *nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
        
        // Explicitly set the metadata on the now playing template
        NSString *title = track[@"title"] ?: @"Unknown Title";
        NSString *artist = track[@"artist"] ?: @"Unknown Artist";
        NSString *album = track[@"album"] ?: @"Unknown Album";
        
        // Create a completely fresh dictionary - prevents inconsistencies
        NSMutableDictionary *updatedInfo = [NSMutableDictionary dictionary];
        
        // Add playback info
        updatedInfo[MPMediaItemPropertyTitle] = title;
        updatedInfo[MPMediaItemPropertyArtist] = artist;
        updatedInfo[MPMediaItemPropertyAlbumTitle] = album;
        
        // Preserve existing artwork if available
        MPMediaItemArtwork *artwork = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo[MPMediaItemPropertyArtwork];
        if (artwork) {
            updatedInfo[MPMediaItemPropertyArtwork] = artwork;
        }
        
        // Preserve playback information
        NSDictionary *currentInfo = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
        if (currentInfo) {
            // Copy playback state info
            NSArray *playbackKeys = @[
                MPNowPlayingInfoPropertyElapsedPlaybackTime,
                MPNowPlayingInfoPropertyPlaybackRate,
                MPNowPlayingInfoPropertyPlaybackQueueIndex,
                MPNowPlayingInfoPropertyPlaybackQueueCount,
                MPMediaItemPropertyPlaybackDuration,
                MPNowPlayingInfoPropertyMediaType,
                MPNowPlayingInfoPropertyIsLiveStream
            ];
            
            for (NSString *key in playbackKeys) {
                id value = currentInfo[key];
                if (value) {
                    updatedInfo[key] = value;
                }
            }
        }
        
        // Set playback rate based on isPlaying
        if (isPlaying != nil) {
            updatedInfo[MPNowPlayingInfoPropertyPlaybackRate] = [isPlaying boolValue] ? @(1.0) : @(0.0);
        }
        
        // Set the updated dictionary
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = updatedInfo;
        
        // Update the interfaceController if available
        if (self.interfaceController && self.connected) {
            // Make sure the template is visible in CarPlay
            dispatch_async(dispatch_get_main_queue(), ^{
                // Show the Now Playing template first time
                static BOOL firstUpdate = YES;
                if (firstUpdate) {
                    firstUpdate = NO;
                    [self showNowPlayingTemplate:nil];
                }
                
                // Ensure that song info always gets refreshed visually on CarPlay
                if (@available(iOS 14.0, *)) {
                    // This forces the Now Playing UI to refresh
                    [nowPlayingTemplate updateNowPlayingButtons:@[]];
                }
            });
            
            // Log extensive debug information
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Now Playing template update completed for track: %@", track[@"title"]]];
            [CDVLogger log:[NSString stringWithFormat:@"CDVCarPlayManager: Now Playing info center contains: %@", [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo]];
        } else {
            [CDVLogger log:@"CDVCarPlayManager WARNING: Cannot show Now Playing template - interface controller is nil or not connected"];
        }
    }
}

- (void)dealloc {
    // Clean up the music player
    if (_musicPlayer) {
        [_musicPlayer cleanup];
    }
    
    // Remove observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];

}

@end
