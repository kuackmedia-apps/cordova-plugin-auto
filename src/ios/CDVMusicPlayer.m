#import "CDVMusicPlayer.h"
#import "CDVCarPlayManager.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@implementation CDVMusicPlayer {
    __weak CDVCarPlayManager *_manager;
    CPNowPlayingTemplate *_nowPlayingTemplate;
    id _timeObserver;
    BOOL _isPlaying;
    NSTimeInterval _lastInfoUpdateTime;
    NSMutableDictionary *_artworkCache;
    BOOL _isUpdatingNowPlayingInfo;
}

#pragma mark - Property Getters

- (NSDictionary *)currentTrack {
    if (_queue.count == 0 || _currentIndex >= _queue.count) {
        return nil;
    }
    return _queue[_currentIndex];
}

- (instancetype)initWithManager:(CDVCarPlayManager *)manager {
    self = [super init];
    if (self) {
        _manager = manager;
        _queue = [NSMutableArray array];
        _currentIndex = 0;
        _isPlaying = NO;
        _lastInfoUpdateTime = 0;
        _artworkCache = [NSMutableDictionary dictionary];
        
        // Setup Audio Session for background playback and CarPlay compatibility
        [self setupAudioSession];
        
        // Create AVPlayer
        _player = [AVPlayer new];
        
        // Add playback status observers
        [self setupPlayerObservers];
        
        // Set up remote command center for CarPlay controls
        [self setupRemoteCommandCenter];
        
        // Setup time observer - reduced frequency (every 5 seconds instead of every 1)
        __weak typeof(self) weakSelf = self;
        _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(5, 1) 
                                                              queue:dispatch_get_main_queue() 
                                                         usingBlock:^(CMTime time) {
            [weakSelf updateNowPlayingInfoIfNeeded];
        }];
        
        // No need for duplicate observer setup - removed
    }
    return self;
}

- (void)setNowPlayingTemplate:(CPNowPlayingTemplate *)nowPlayingTemplate {
    _nowPlayingTemplate = nowPlayingTemplate;
}

#pragma mark - Playback Control

- (void)play {
    if (_queue.count == 0) {
        NSLog(@"CDVMusicPlayer: Cannot play - queue is empty");
        return;
    }
    
    if (_player.currentItem == nil || _player.currentItem.status != AVPlayerItemStatusReadyToPlay) {
        NSLog(@"CDVMusicPlayer: Loading current track before playing");
        [self loadCurrentTrack];
    }
    
    NSLog(@"CDVMusicPlayer: Starting playback");
    [_player play];
    _isPlaying = YES;
    
    // Make sure MPNowPlayingInfoCenter is updated before showing the template
    [self updateNowPlayingInfoIfNeeded];
    
    // Force CarPlay to show the Now Playing screen when playback starts
    if (_player.currentItem) {
        NSLog(@"CDVMusicPlayer: Activating Now Playing template in CarPlay");
        dispatch_async(dispatch_get_main_queue(), ^{
            // Get reference to the interface controller from our manager
            // We need to notify our manager to show the now playing template
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVShowNowPlayingTemplate" 
                                                               object:nil 
                                                             userInfo:nil];
        });
    }
}

- (void)pause {
    NSLog(@"CDVMusicPlayer: pause called");
    [_player pause];
    _isPlaying = NO;
    [self updateNowPlayingInfoIfNeeded];
}

- (void)togglePlayPause {
    NSLog(@"CDVMusicPlayer: togglePlayPause called");
    if (_isPlaying) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)skipToNext {
    if (_queue.count == 0) {
        return;
    }
    
    _currentIndex = (_currentIndex + 1) % _queue.count;
    [self loadCurrentTrack];
    // Reset lastInfoUpdateTime to force immediate update with new track
    _lastInfoUpdateTime = 0;
    [self play];
}

- (void)skipToPrevious {
    if (_queue.count == 0) {
        return;
    }
    
    _currentIndex = (_currentIndex - 1 + _queue.count) % _queue.count;
    [self loadCurrentTrack];
    // Reset lastInfoUpdateTime to force immediate update with new track
    _lastInfoUpdateTime = 0;
    [self play];
}

- (void)seekToPosition:(double)position {
    [_player seekToTime:CMTimeMakeWithSeconds(position / 1000.0, NSEC_PER_SEC)];
}

- (double)currentPlaybackPosition {
    return CMTimeGetSeconds(_player.currentTime) * 1000.0;
}

- (NSString *)currentPlaybackState {
    if (_isPlaying) {
        return @"playing";
    } else if (_player.currentItem != nil) {
        return @"paused";
    } else {
        return @"stopped";
    }
}

#pragma mark - Queue Management

- (void)updateQueue:(NSArray *)queue {
    _queue = queue;
    _currentIndex = 0;
    
    if (_queue.count > 0) {
        [self loadCurrentTrack];
        [self updateNowPlayingInfo];
    }
}

- (void)reloadQueue {
    // This would typically reload the queue from storage
    // For this implementation, we'll just use the existing queue
}

- (void)updateCurrentTrack {
    if (_queue.count > 0) {
        [self loadCurrentTrack];
        [self updateNowPlayingInfo];
    }
}

#pragma mark - Private Methods

- (void)loadCurrentTrack {
    NSLog(@"CDVMusicPlayer: loadCurrentTrack called. Current queue size: %lu, currentIndex: %ld", 
          (unsigned long)_queue.count, (long)_currentIndex);
    
    if (_queue.count == 0) {
        NSLog(@"CDVMusicPlayer ERROR: Cannot load current track - queue is empty");
        return;
    }
    
    if (_currentIndex >= _queue.count) {
        NSLog(@"CDVMusicPlayer: Current index out of bounds. Resetting to 0.");
        _currentIndex = 0;
    }
    
    NSDictionary *track = _queue[_currentIndex];
    NSLog(@"CDVMusicPlayer: Loading track: %@", track);
    
    NSString *mediaUrl = track[@"source"];
    
    if (!mediaUrl) {
        NSLog(@"CDVMusicPlayer ERROR: Track has no source URL. Track data: %@", track);
        return;
    }
    
    // Clear the artwork cache for this track to ensure we reload it
    NSString *imagePath = track[@"image"];
    if (imagePath) {
        [_artworkCache removeObjectForKey:imagePath];
    }
    
    NSLog(@"CDVMusicPlayer: Creating player item with URL: %@", mediaUrl);
    
    // Create a new player item
    NSURL *url = [NSURL URLWithString:mediaUrl];
    if (!url) {
        NSLog(@"CDVMusicPlayer ERROR: Failed to create URL from string: %@", mediaUrl);
        return;
    }
    
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:url];
    if (!playerItem) {
        NSLog(@"CDVMusicPlayer ERROR: Failed to create AVPlayerItem with URL: %@", url);
        return;
    }
    
    // Replace the current item
    NSLog(@"CDVMusicPlayer: Replacing current player item");
    [_player replaceCurrentItemWithPlayerItem:playerItem];
    
    // Notify about track change
    NSLog(@"CDVMusicPlayer: Posting track change notification");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVMediaTrackChanged" 
                                                    object:nil 
                                                  userInfo:@{@"track": track}];
}

- (void)nextTrack {
    [self skipToNext];
}

- (void)previousTrack {
    [self skipToPrevious];
}

- (void)updateNowPlayingInfoIfNeeded {
    // Throttle updates to no more than once per second
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - _lastInfoUpdateTime < 1.0 && _isUpdatingNowPlayingInfo == NO) {
        return; // Skip update if less than 1 second has passed since the last update
    }
    
    _lastInfoUpdateTime = now;
    [self updateNowPlayingInfo];
}

- (void)updateNowPlayingInfo {
    if (_queue.count == 0 || _currentIndex >= _queue.count) {
        return;
    }
    
    // Prevent concurrent updates
    if (_isUpdatingNowPlayingInfo) {
        return;
    }
    
    _isUpdatingNowPlayingInfo = YES;
    
    // Declare artwork variable at the beginning to avoid scope issues
    UIImage *artwork = nil;
    
    NSDictionary *track = _queue[_currentIndex];
    NSLog(@"CDVMusicPlayer: Updating now playing info for track: %@", track[@"title"]);
    
    // Create the now playing info
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    
    // Debug information
    NSLog(@"CDVMusicPlayer: Current track metadata - Title: %@, Artist: %@, Album: %@", 
          track[@"title"] ?: @"nil",
          track[@"artist"] ?: @"nil",
          track[@"album"] ?: @"nil");
    
    // Add metadata - make sure to have non-nil values
    nowPlayingInfo[MPMediaItemPropertyTitle] = track[@"title"] ?: @"Unknown Title";
    nowPlayingInfo[MPMediaItemPropertyArtist] = track[@"artist"] ?: @"Unknown Artist";
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track[@"album"] ?: @"Unknown Album";
    
    // Add playback info
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(_player.currentTime));
    
    if (_player.currentItem) {
        CMTime duration = _player.currentItem.duration;
        if (CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration)) {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(CMTimeGetSeconds(duration));
        } else {
            // If duration is not valid, provide a reasonable default
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(180.0); // Default 3 minutes
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = _isPlaying ? @(1.0) : @(0.0);
    }
    
    // Add essential properties for CarPlay
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = @(NO);
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = @(MPMediaTypeMusic);
    
    // Add artwork
    NSString *imagePath = track[@"image"];
    if (imagePath) {
        // Check if artwork is already cached
        UIImage *artwork = _artworkCache[imagePath];
        
        // If not in cache, load asynchronously
        if (!artwork) {
            if ([imagePath hasPrefix:@"http://"] || [imagePath hasPrefix:@"https://"]) {
                // Load from URL asynchronously
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSURL *imageURL = [NSURL URLWithString:imagePath];
                    NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
                    UIImage *loadedImage = nil;
                    
                    if (imageData) {
                        loadedImage = [UIImage imageWithData:imageData];
                        if (loadedImage) {
                            // Cache the image
                            dispatch_async(dispatch_get_main_queue(), ^{
                                self->_artworkCache[imagePath] = loadedImage;
                                // Set the now playing info again with the loaded image
                                [self updateNowPlayingInfoWithArtwork:loadedImage track:track nowPlayingInfo:nowPlayingInfo];
                            });
                        }
                    }
                    
                    // Ensure we finish updating if image loading fails
                    if (!loadedImage) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self updateNowPlayingInfoWithArtwork:nil track:track nowPlayingInfo:nowPlayingInfo];
                        });
                    }
                });
                
                // Continue with other updates while image loads
                artwork = nil;
            } else {
                // Try to load from bundle (this is quick enough to do on main thread)
                artwork = [UIImage imageNamed:imagePath];
                if (artwork) {
                    _artworkCache[imagePath] = artwork; // Cache it
                }
            }
        }
        
        // Fall back to default artwork if we failed to load
        if (!artwork) {
            artwork = [UIImage imageNamed:@"default_art"];
            // If still nil, create a colored placeholder
            if (!artwork) {
                // Create a simple colored square with the first letter of the song
                CGRect rect = CGRectMake(0, 0, 600, 600);
                UIGraphicsBeginImageContext(rect.size);
                CGContextRef context = UIGraphicsGetCurrentContext();
                
                // Fill background with color based on first letter of title
                NSString *title = track[@"title"] ?: @"Unknown";
                unichar firstChar = [title characterAtIndex:0];
                CGFloat hue = (firstChar % 26) / 26.0;
                UIColor *color = [UIColor colorWithHue:hue saturation:0.7 brightness:0.7 alpha:1.0];
                
                CGContextSetFillColorWithColor(context, [color CGColor]);
                CGContextFillRect(context, rect);
                
                // Add text
                NSString *text = [title substringToIndex:1];
                UIFont *font = [UIFont boldSystemFontOfSize:300];
                NSDictionary *attributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]};
                CGSize textSize = [text sizeWithAttributes:attributes];
                CGRect textRect = CGRectMake((rect.size.width - textSize.width) / 2, 
                                            (rect.size.height - textSize.height) / 2, 
                                            textSize.width, 
                                            textSize.height);
                [text drawInRect:textRect withAttributes:attributes];
                
                artwork = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
        }
        
        if (artwork) {
            MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size 
                                                                         requestHandler:^UIImage * _Nonnull(CGSize size) {
                return artwork;
            }];
            nowPlayingInfo[MPMediaItemPropertyArtwork] = albumArt;
        }
    } else {
        // Create default artwork if no image path is provided
        CGRect rect = CGRectMake(0, 0, 600, 600);
        UIGraphicsBeginImageContext(rect.size);
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        // Simple gradient background
        CGContextSetFillColorWithColor(context, [[UIColor darkGrayColor] CGColor]);
        CGContextFillRect(context, rect);
        
        UIImage *artwork = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        if (artwork) {
            MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size 
                                                                         requestHandler:^UIImage * _Nonnull(CGSize size) {
                return artwork;
            }];
            nowPlayingInfo[MPMediaItemPropertyArtwork] = albumArt;
        }
    }
    
    // If we're doing async image loading, we'll return early and let the async path complete
    if ([imagePath hasPrefix:@"http://"] || [imagePath hasPrefix:@"https://"] && !artwork) {
        return;
    }
    
    // Otherwise, complete the update with the current artwork state
    [self updateNowPlayingInfoWithArtwork:artwork track:track nowPlayingInfo:nowPlayingInfo];
}

- (void)updateNowPlayingInfoWithArtwork:(UIImage *)artwork track:(NSDictionary *)track nowPlayingInfo:(NSMutableDictionary *)nowPlayingInfo {
    // Add the artwork to the now playing info if available
    if (artwork) {
        MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size 
                                                                 requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = albumArt;
    }
    
    NSLog(@"CDVMusicPlayer: Setting now playing info center with: %@", nowPlayingInfo);
    
    // Set the now playing info
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    
    // Update CarPlay now playing template if available - only if we're not in the middle of another update
    if (_nowPlayingTemplate) {
        // Consolidate all notifications into a single update
        dispatch_async(dispatch_get_main_queue(), ^{
            // Only post a single notification with all relevant info
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVUpdateNowPlayingTemplate" 
                                                           object:nil 
                                                         userInfo:@{@"track": track, @"isPlaying": @(self->_isPlaying)}];
        });
    }
    
    // Mark update as finished
    _isUpdatingNowPlayingInfo = NO;
}

- (void)updatePlaybackState:(NSString *)state {
    // This method is now only used for explicit external status updates
    // For normal playback state changes, the status is sent alongside the track info
    // to avoid multiple notifications
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVPlaybackStateChanged" 
                                                    object:nil 
                                                  userInfo:@{@"state": state}];
}

#pragma mark - Audio Session and Remote Controls

- (void)setupAudioSession {
    NSLog(@"CDVMusicPlayer: Setting up audio session for background playback and CarPlay");
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    // Use playback category with appropriate options for CarPlay
    if (@available(iOS 10.0, *)) {
        // Use .allowAirPlay for CarPlay support
        [session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:(AVAudioSessionCategoryOptionAllowBluetooth |
                              AVAudioSessionCategoryOptionAllowAirPlay |
                              AVAudioSessionCategoryOptionMixWithOthers)
                        error:&error];
    } else {
        [session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                        error:&error];
    }
    
    if (error) {
        NSLog(@"CDVMusicPlayer ERROR: Failed to set audio session category: %@", error);
        error = nil; // Reset error for next operation
    }
    
    // Set audio session mode to support movie playback (includes music)
    [session setMode:AVAudioSessionModeMoviePlayback error:&error];
    if (error) {
        NSLog(@"CDVMusicPlayer ERROR: Failed to set audio session mode: %@", error);
        error = nil; // Reset error for next operation
    }
    
    // Register for interruption notifications
    [self registerForAudioInterruptions];
    
    // Set session active with options to ensure playback continues in background
    [session setActive:YES 
            withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation 
                  error:&error];
    
    if (error) {
        NSLog(@"CDVMusicPlayer ERROR: Failed to activate audio session: %@", error);
    } else {
        NSLog(@"CDVMusicPlayer: Audio session successfully activated with background playback support");
    }
}

- (void)setupRemoteCommandCenter {
    NSLog(@"CDVMusicPlayer: Setting up remote command center for CarPlay controls");
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    
    // Remove all targets first to avoid duplicates
    [commandCenter.playCommand removeTarget:nil];
    [commandCenter.pauseCommand removeTarget:nil];
    [commandCenter.togglePlayPauseCommand removeTarget:nil];
    [commandCenter.nextTrackCommand removeTarget:nil];
    [commandCenter.previousTrackCommand removeTarget:nil];
    
    // Enable and add handlers for media control commands
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"CDVMusicPlayer: Remote play command received");
        [self play];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"CDVMusicPlayer: Remote pause command received");
        [self pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"CDVMusicPlayer: Remote toggle play/pause command received");
        if (self->_isPlaying) {
            [self pause];
        } else {
            [self play];
        }
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"CDVMusicPlayer: Remote next track command received");
        [self skipToNext];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"CDVMusicPlayer: Remote previous track command received");
        [self skipToPrevious];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // Enable all commands
    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.togglePlayPauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;
}

- (void)registerForAudioInterruptions {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    // Register for audio interruption notifications
    [center addObserver:self
               selector:@selector(handleAudioSessionInterruption:)
                   name:AVAudioSessionInterruptionNotification
                 object:nil];
    
    // Register for route change notifications (important for CarPlay)
    [center addObserver:self
               selector:@selector(handleAudioRouteChange:)
                   name:AVAudioSessionRouteChangeNotification
                 object:nil];
                 
    // Register for media server reset notifications
    [center addObserver:self
               selector:@selector(handleMediaServerReset:)
                   name:AVAudioSessionMediaServicesWereResetNotification
                 object:nil];
}

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    NSLog(@"CDVMusicPlayer: Handling audio session interruption");
    NSInteger interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
    
    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        // Interruption began, pause playback
        NSLog(@"CDVMusicPlayer: Audio session interruption began");
        if (_isPlaying) {
            [self pause];
        }
    } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        // Interruption ended, resume playback if option is set
        NSLog(@"CDVMusicPlayer: Audio session interruption ended");
        NSInteger interruptionOption = [notification.userInfo[AVAudioSessionInterruptionOptionKey] integerValue];
        if (interruptionOption == AVAudioSessionInterruptionOptionShouldResume && _player.currentItem != nil) {
            // Re-activate audio session if needed
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (error) {
                NSLog(@"CDVMusicPlayer: Failed to reactivate audio session after interruption: %@", error);
            } else {
                // Only auto-resume if we were playing before
                NSLog(@"CDVMusicPlayer: Audio session reactivated after interruption");
                [self play];
            }
        }
    }
}

- (void)handleAudioRouteChange:(NSNotification *)notification {
    NSLog(@"CDVMusicPlayer: Audio route changed");
    NSInteger routeChangeReason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue];
    
    // Get the current route
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    NSLog(@"CDVMusicPlayer: Current audio route: %@", currentRoute);
    
    switch (routeChangeReason) {
        case AVAudioSessionRouteChangeReasonCategoryChange:
            NSLog(@"CDVMusicPlayer: Audio route change: Category changed");
            break;
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"CDVMusicPlayer: Audio route change: Old device unavailable");
            // Pause when headphones are unplugged, etc.
            if (_isPlaying) {
                [self pause];
            }
            break;
            
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"CDVMusicPlayer: Audio route change: New device available");
            // This happens when CarPlay connects or headphones plugged in
            // Force refresh now playing info
            [self updateNowPlayingInfo];
            break;
            
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"CDVMusicPlayer: Audio route change: Override");
            // This often happens with CarPlay activation
            [self updateNowPlayingInfo];
            break;
            
        default:
            NSLog(@"CDVMusicPlayer: Audio route change reason: %ld", (long)routeChangeReason);
            break;
    }
}

- (void)handleMediaServerReset:(NSNotification *)notification {
    NSLog(@"CDVMusicPlayer: Media server reset occurred");
    
    // Recreate audio session
    [self setupAudioSession];
    
    // If we were playing, try to resume
    if (_isPlaying) {
        [self pause]; // Reset state first
        [self loadCurrentTrack]; // Reload current track
        [self play]; // Resume playback
    }
}

- (void)setupPlayerObservers {
    // Observe player item status
    [_player addObserver:self 
              forKeyPath:@"currentItem.status" 
                 options:NSKeyValueObservingOptionNew 
                 context:nil];
    
    // Observe player rate
    [_player addObserver:self 
              forKeyPath:@"rate" 
                 options:NSKeyValueObservingOptionNew 
                 context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"currentItem.status"]) {
        AVPlayerItemStatus status = [change[NSKeyValueChangeNewKey] integerValue];
        if (status == AVPlayerItemStatusReadyToPlay) {
            if (_isPlaying) {
                [_player play];
            }
        } else if (status == AVPlayerItemStatusFailed) {
            NSLog(@"Player item failed: %@", _player.currentItem.error);
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        float rate = [change[NSKeyValueChangeNewKey] floatValue];
        _isPlaying = (rate != 0);
        [self updatePlaybackState:_isPlaying ? @"playing" : @"paused"];
    }
}

- (void)playTrack:(NSDictionary *)track {
    if (!track || !track[@"url"]) {
        NSLog(@"Cannot play track: missing URL");
        return;
    }
    
    NSString *mediaUrl = track[@"url"];
    
    // Create a new player item
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:mediaUrl]];
    
    // Replace the current item
    [_player replaceCurrentItemWithPlayerItem:playerItem];
    
    // Create a temporary queue with just this track
    NSMutableArray *tempQueue = [NSMutableArray array];
    [tempQueue addObject:@{
        @"id": track[@"id"] ?: @"hardcoded_track",
        @"title": track[@"title"] ?: @"Unknown Title",
        @"artist": track[@"artist"] ?: @"Unknown Artist",
        @"album": track[@"album"] ?: @"Unknown Album",
        @"source": mediaUrl
    }];
    
    // Update the queue
    _queue = tempQueue;
    _currentIndex = 0;
    
    // Start playback
    [self play];
    
    // Notify about track change
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVMediaTrackChanged" 
                                                     object:nil 
                                                   userInfo:@{@"track": track}];
}

- (void)cleanup {
    // Remove observers
    [_player removeObserver:self forKeyPath:@"currentItem.status"];
    [_player removeObserver:self forKeyPath:@"rate"];
    
    // Remove time observer
    if (_timeObserver) {
        [_player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    
    // Stop playback
    [_player pause];
    _player = nil;
    
    // Clear queue
    _queue = @[];
    _currentIndex = 0;
    
    // Clear artwork cache
    [_artworkCache removeAllObjects];
    _isUpdatingNowPlayingInfo = NO;
}

@end
