#import "CDVCarPlayManager.h"
#import "CDVAutoMusicPlugin.h"
#import "CDVMusicPlayer.h"
#import "CDVPlaylistProvider.h"

// Define CarPlay constants if not available
#ifndef CPNowPlayingTitleKey
#define CPNowPlayingTitleKey MPMediaItemPropertyTitle
#endif

#ifndef CPNowPlayingSubtitleKey
#define CPNowPlayingSubtitleKey MPMediaItemPropertyArtist
#endif

#ifndef CPNowPlayingAlbumTitleKey
#define CPNowPlayingAlbumTitleKey MPMediaItemPropertyAlbumTitle
#endif

#ifndef CPNowPlayingImageKey
#define CPNowPlayingImageKey MPMediaItemPropertyArtwork
#endif

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
    NSLog(@"CDVCarPlayManager: setupTemplates starting...");
    
    if (!interfaceController) {
        NSLog(@"CDVCarPlayManager ERROR: interfaceController is nil in setupTemplates");
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
    
    NSLog(@"CDVCarPlayManager: Templates setup completed. TabBar template: %@, Playlists template: %@, NowPlaying template: %@", 
          _tabBarTemplate, _playlistsTemplate, _nowPlayingTemplate);
}

- (void)setupRootTemplate:(CPInterfaceController *)interfaceController {
    NSLog(@"⚠️ CDVCarPlayManager: setupRootTemplate starting...");
    
    // Verificar que el interfaceController es válido
    if (!interfaceController) {
        NSLog(@"❌ CDVCarPlayManager ERROR: interfaceController is nil");
        return;
    }
    self.interfaceController = interfaceController;
    
    // Create the now playing template
    _nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
    
    // Create the playlists template as a fallback
    _playlistsTemplate = [self createPlaylistsTemplate];
    if (!_playlistsTemplate) {
        NSLog(@"❌ CDVCarPlayManager ERROR: Failed to create playlists template");
        return;
    }
    
    // INTENTO 1: Crear un template básico sin tabs para probar si funciona
    CPListTemplate *simpleTemplate = [[CPListTemplate alloc] initWithTitle:@"Music" sections:@[]];
    if (!simpleTemplate) {
        NSLog(@"❌ No se pudo crear template básico");
    }
    
    // INTENTO 2: Crear tabs individualmente
    CPListTemplate *libraryTemplate = [self createPlaylistsTemplate];
    libraryTemplate.tabTitle = @"Biblioteca";
    libraryTemplate.tabImage = [UIImage systemImageNamed:@"music.note.list"];
    
    CPListTemplate *recentTemplate = [[CPListTemplate alloc] initWithTitle:@"Recientes" sections:@[]];
    recentTemplate.tabTitle = @"Recientes";
    recentTemplate.tabImage = [UIImage systemImageNamed:@"clock"];
    
    CPListTemplate *exploreTemplate = [[CPListTemplate alloc] initWithTitle:@"Explorar" sections:@[]];
    exploreTemplate.tabTitle = @"Explorar";
    exploreTemplate.tabImage = [UIImage systemImageNamed:@"square.grid.2x2"];
    
    // Crear el TabBarTemplate con los templates individuales
    CPTabBarTemplate *tabBarTemplate = [[CPTabBarTemplate alloc] initWithTemplates:@[libraryTemplate, recentTemplate, exploreTemplate]];
    
    // Verificar si se creó correctamente
    if (tabBarTemplate) {
        NSLog(@"✅ TabBarTemplate creado correctamente");
    } else {
        NSLog(@"❌ Fallo al crear TabBarTemplate");
    }
    
    // Establecer el TabBarTemplate como root
    NSLog(@"⚠️ Intentando establecer TabBarTemplate como root...");
    [self.interfaceController setRootTemplate:tabBarTemplate animated:YES completion:^(BOOL success, NSError *error) {
        if (error) {
            NSLog(@"❌ ERROR al establecer TabBarTemplate: %@", error);
            // Intentar con el template básico
            [self.interfaceController setRootTemplate:simpleTemplate animated:YES completion:^(BOOL success, NSError *error) {
                if (error) {
                    NSLog(@"❌ ERROR al establecer template básico: %@", error);
                    // Fallback final al template de playlists
                    [self.interfaceController setRootTemplate:self->_playlistsTemplate animated:YES completion:nil];
                } else {
                    NSLog(@"✅ Template básico establecido correctamente");
                }
            }];
        } else {
            NSLog(@"✅ TabBarTemplate establecido correctamente: %@", success ? @"YES" : @"NO");
        }
    }];
}

- (CPTabBarTemplate *)createNavigationTemplate {
    NSLog(@"CDVCarPlayManager: createNavigationTemplate starting...");
    
    // Get navigation items from AUTO_NAVIGATION
    NSArray *navigationItems = [CDVPlaylistProvider loadNavigationFromJSON];
    NSLog(@"CDVCarPlayManager: Got %lu navigation items from AUTO_NAVIGATION", (unsigned long)navigationItems.count);
    
    if (navigationItems.count == 0) {
        NSLog(@"CDVCarPlayManager WARNING: No navigation items returned from provider");
        // Return a tab bar template with just a playlists tab as fallback
        CPListTemplate *playlistsTemplate = [self createPlaylistsTemplate];
        return [[CPTabBarTemplate alloc] initWithTemplates:@[playlistsTemplate]];
    }
    
    // Create template items for each navigation area (Recientes, Biblioteca, Explorar)
    NSMutableArray *tabTemplates = [NSMutableArray array];
    
    for (NSDictionary *navItem in navigationItems) {
        NSString *text = navItem[@"text"];
        NSString *fileName = navItem[@"fileName"];
        
        if (!text || !fileName) {
            NSLog(@"CDVCarPlayManager ERROR: Navigation item missing required fields: %@", navItem);
            continue;
        }
        
        NSLog(@"CDVCarPlayManager: Creating tab template for: %@ (file: %@)", text, fileName);
        
        // Create appropriate template based on the navigation section
        CPTemplate *sectionTemplate = nil;
        
        // Get SF Symbol from navigation item or use fallback
        NSString *iconName = navItem[@"sfSymbol"];
        if (!iconName) {
            // If no sfSymbol specified, try to use a default based on the section
            if ([fileName isEqualToString:@"AUTO_NAVIGATION_LIBRARY"]) {
                iconName = @"music.note.list";
            } else if ([fileName isEqualToString:@"RECENT_LISTENED"]) {
                iconName = @"clock";
            } else if ([fileName isEqualToString:@"AUTO_NAVIGATION_EXPLORER"]) {
                iconName = @"square.grid.2x2";
            } else {
                iconName = @"questionmark.circle"; // Default fallback
            }
        }
        
        if ([fileName isEqualToString:@"AUTO_NAVIGATION_LIBRARY"]) {
            // Library section - shows playlists from AUTO_NAVIGATION_LIBRARY
            CPListTemplate *libraryTemplate = [self createTemplateForFileName:fileName withTitle:text];
            libraryTemplate.tabTitle = text;
            libraryTemplate.tabImage = [UIImage systemImageNamed:iconName];
            sectionTemplate = libraryTemplate;
            
        } else if ([fileName isEqualToString:@"RECENT_LISTENED"]) {
            // Recents section - loads from RECENT_LISTENED
            CPListTemplate *recentsTemplate = [self createTemplateForFileName:fileName withTitle:text];
            recentsTemplate.tabTitle = text;
            recentsTemplate.tabImage = [UIImage systemImageNamed:iconName];
            sectionTemplate = recentsTemplate;
            
        } else if ([fileName isEqualToString:@"AUTO_NAVIGATION_EXPLORER"]) {
            // Explorer section - loads from AUTO_NAVIGATION_EXPLORER
            CPListTemplate *explorerTemplate = [self createTemplateForFileName:fileName withTitle:text];
            explorerTemplate.tabTitle = text;
            explorerTemplate.tabImage = [UIImage systemImageNamed:iconName];
            sectionTemplate = explorerTemplate;
        }
        
        if (sectionTemplate) {
            [tabTemplates addObject:sectionTemplate];
        }
    }
    
    // Create tab bar template with all the navigation tab templates
    if (tabTemplates.count == 0) {
        NSLog(@"CDVCarPlayManager WARNING: No valid tab templates created");
        // Return a tab bar template with just a playlists tab as fallback
        CPListTemplate *playlistsTemplate = [self createPlaylistsTemplate];
        return [[CPTabBarTemplate alloc] initWithTemplates:@[playlistsTemplate]];
    }
    
    NSLog(@"CDVCarPlayManager: Created tab bar template with %lu tabs", (unsigned long)tabTemplates.count);
    CPTabBarTemplate *tabBarTemplate = [[CPTabBarTemplate alloc] initWithTemplates:tabTemplates];
    
    return tabBarTemplate;
}

- (CPListTemplate *)createTemplateForFileName:(NSString *)fileName withTitle:(NSString *)title {
    NSLog(@"🔍 CDVCarPlayManager: Creating template for %@ with title %@", fileName, title);
    
    // Contenedor para las secciones de la lista
    NSMutableArray *sections = [NSMutableArray array];
    
    // Process different file types
    if ([fileName isEqualToString:@"AUTO_NAVIGATION_LIBRARY"]) {
        NSLog(@"📚 CDVCarPlayManager: Loading library data...");
        // Para biblioteca - usamos la plantilla de playlists ya implementada
        return [self createPlaylistsTemplate];
    } 
    else if ([fileName isEqualToString:@"RECENT_LISTENED"]) {
        NSLog(@"🕒 CDVCarPlayManager: Loading recent data...");
        // Cargar escuchas recientes
        NSArray *recentItems = [CDVPlaylistProvider loadJSONFromFile:fileName inDirectory:@"navigation"];
        
        if (recentItems && [recentItems isKindOfClass:[NSArray class]] && recentItems.count > 0) {
            NSLog(@"✅ Found %lu recent items", (unsigned long)recentItems.count);
            NSMutableArray *listItems = [NSMutableArray array];
            
            for (NSDictionary *item in recentItems) {
                NSString *itemName = item[@"name"] ?: @"Sin nombre";
                
                // Extraer subtítulo
                NSString *subtitleText = nil;
                if (item[@"curator"] && [item[@"curator"] isKindOfClass:[NSDictionary class]]) {
                    subtitleText = item[@"curator"][@"name"];
                } else if (item[@"description"]) {
                    subtitleText = item[@"description"];
                }
                
                CPListItem *listItem = [[CPListItem alloc] initWithText:itemName detailText:subtitleText];
                
                // Manejador cuando se selecciona un ítem
                __weak __typeof__(self) weakSelf = self;
                listItem.handler = ^(CPListItem * _Nonnull item, dispatch_block_t  _Nonnull completion) {
                    NSLog(@"👆 Selected recent item: %@", item.text);
                    completion();
                };
                
                [listItems addObject:listItem];
            }
            
            if (listItems.count > 0) {
                CPListSection *recentSection = [[CPListSection alloc] initWithItems:listItems header:@"Recientes" sectionIndexTitle:nil];
                [sections addObject:recentSection];
            }
        } else {
            NSLog(@"⚠️ No recent items found or invalid data format");
            // Crear una sección vacía para evitar errores
            CPListSection *emptySection = [[CPListSection alloc] initWithItems:@[] header:@"No hay elementos recientes" sectionIndexTitle:nil];
            [sections addObject:emptySection];
        }
    } 
    else if ([fileName isEqualToString:@"AUTO_NAVIGATION_EXPLORER"]) {
        NSLog(@"🌐 CDVCarPlayManager: Loading explorer data...");
        // Cargar datos de explorador
        NSArray *explorerItems = [CDVPlaylistProvider loadJSONFromFile:fileName inDirectory:@"navigation"];
        
        if (explorerItems && [explorerItems isKindOfClass:[NSArray class]] && explorerItems.count > 0) {
            NSLog(@"✅ Found %lu explorer items", (unsigned long)explorerItems.count);
            NSMutableArray *listItems = [NSMutableArray array];
            
            for (NSDictionary *item in explorerItems) {
                NSString *itemName = item[@"name"] ?: @"Sin nombre";
                NSString *itemType = item[@"type"] ?: @"";
                
                CPListItem *listItem = [[CPListItem alloc] initWithText:itemName detailText:itemType];
                
                // Manejador cuando se selecciona un ítem
                __weak __typeof__(self) weakSelf = self;
                listItem.handler = ^(CPListItem * _Nonnull item, dispatch_block_t  _Nonnull completion) {
                    NSLog(@"👆 Selected explorer item: %@", item.text);
                    completion();
                };
                
                [listItems addObject:listItem];
            }
            
            if (listItems.count > 0) {
                CPListSection *explorerSection = [[CPListSection alloc] initWithItems:listItems header:@"Categorías" sectionIndexTitle:nil];
                [sections addObject:explorerSection];
            }
        } else {
            NSLog(@"⚠️ No explorer items found or invalid data format");
            // Crear una sección vacía para evitar errores
            CPListSection *emptySection = [[CPListSection alloc] initWithItems:@[] header:@"No hay elementos para explorar" sectionIndexTitle:nil];
            [sections addObject:emptySection];
        }
    } else {
        NSLog(@"⚠️ Unknown file name: %@", fileName);
        // Crear una sección vacía para archivo desconocido
        CPListSection *emptySection = [[CPListSection alloc] initWithItems:@[] header:@"No hay contenido" sectionIndexTitle:nil];
        [sections addObject:emptySection];
    }
    
    // Crear la plantilla con las secciones
    CPListTemplate *template = [[CPListTemplate alloc] initWithTitle:title sections:sections];
    NSLog(@"✅ Created template for %@ with %lu sections", fileName, (unsigned long)sections.count);
    return template;
}

- (CPListTemplate *)createPlaylistsTemplate {
    NSLog(@"CDVCarPlayManager: Creating playlists template");
    
    NSArray *playlists = [CDVPlaylistProvider loadPlaylistsFromJSON];
    NSLog(@"🔍 CDVCarPlayManager: Loaded %lu playlists", (unsigned long)[playlists count]);
    
    if (playlists.count == 0) {
        NSLog(@"CDVCarPlayManager WARNING: No playlists returned from provider");
    }
    
    // Create a list template for playlists
    NSMutableArray *playlistItems = [NSMutableArray array];
    
    // Create list items for each playlist
    for (NSDictionary *playlist in playlists) {
        NSLog(@"CDVCarPlayManager: Creating item for playlist: %@", playlist[@"title"]);
        
        // Ensure required fields exist
        if (!playlist[@"title"] || !playlist[@"id"]) {
            NSLog(@"CDVCarPlayManager ERROR: Playlist missing required fields: %@", playlist);
            continue;
        }
        
        CPListItem *item = [[CPListItem alloc] initWithText:playlist[@"title"] 
                                               detailText:playlist[@"description"]];
        
        // Set handler for when a playlist is selected
        __weak __typeof__(self) weakSelf = self;
        item.handler = ^(CPListItem * _Nonnull item, dispatch_block_t  _Nonnull completion) {
            NSLog(@"CDVCarPlayManager: Playlist selected: %@", item.text);
            
            // Load tracks from JSON files for the selected playlist
            NSArray *tracks = [CDVPlaylistProvider loadTracksForPlaylist:playlist[@"id"]];
            NSLog(@"CDVCarPlayManager: Got %lu tracks from JSON for playlist %@", (unsigned long)tracks.count, playlist[@"id"]);
            
            if (tracks.count == 0) {
                NSLog(@"CDVCarPlayManager WARNING: No tracks returned for playlist %@, falling back to hardcoded tracks", playlist[@"id"]);
                // Try fallback to hardcoded tracks
                tracks = [CDVPlaylistProvider tracksForPlaylist:playlist[@"id"]];
            }
            
            [weakSelf.musicPlayer updateQueue:tracks];
            [weakSelf.musicPlayer play];
            completion();
        };
        
        [playlistItems addObject:item];
    }
    
    NSLog(@"CDVCarPlayManager: Created %lu playlist items", (unsigned long)playlistItems.count);
    
    // Create a section with the playlist items
    CPListSection *section = [[CPListSection alloc] initWithItems:playlistItems];
    
    // Create the list template with the section
    CPListTemplate *listTemplate = [[CPListTemplate alloc] initWithTitle:@"Playlists" sections:@[section]];
    NSLog(@"CDVCarPlayManager: Created playlist template with title 'Playlists' and %lu sections", 
          (unsigned long)listTemplate.sections.count);
    
    return listTemplate;
}

- (void)setupNowPlayingTemplate {
    NSLog(@"CDVCarPlayManager: Setting up now playing template");
    
    // Get the shared template - this is a singleton provided by the system
    _nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
    
    // Configure the now playing template
    _nowPlayingTemplate.albumArtistButtonEnabled = YES;
    _nowPlayingTemplate.upNextButtonEnabled = YES;
    
    // Needed for iOS 14+: make sure template is properly configured with buttons
    if (@available(iOS 14.0, *)) {
        NSLog(@"CDVCarPlayManager: Setting up now playing template with explicit button configurations");
        
        // For newer iOS versions, the buttons are automatically configured by the system
        // No need to create or configure them manually
        NSLog(@"CDVCarPlayManager: Using system-provided Now Playing buttons in iOS 14+");
        
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
    
    NSLog(@"CDVCarPlayManager: Now playing template setup complete");
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
    NSLog(@"CDVCarPlayManager: Received request to show Now Playing template");
    
    if (!self.interfaceController) {
        NSLog(@"CDVCarPlayManager ERROR: Cannot show Now Playing template - interface controller is nil");
        return;
    }
    
    // Prevent redundant template displays
    static BOOL isTemplateDisplayInProgress = NO;
    if (isTemplateDisplayInProgress) {
        NSLog(@"CDVCarPlayManager: Template display already in progress, skipping duplicate request");
        return;
    }
    
    isTemplateDisplayInProgress = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Get the Now Playing template
        CPNowPlayingTemplate *nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
        
        // Check if the Now Playing template is already the top-level template
        if ([self.interfaceController.topTemplate isKindOfClass:[CPNowPlayingTemplate class]]) {
            NSLog(@"CDVCarPlayManager: Now Playing template is already displayed, skipping push");
            isTemplateDisplayInProgress = NO;
            return;
        }
                
        // Push the Now Playing template onto the navigation stack
        [self.interfaceController pushTemplate:nowPlayingTemplate animated:YES completion:^(BOOL success, NSError * _Nullable error) {
            isTemplateDisplayInProgress = NO;
            
            if (!success) {
                NSLog(@"CDVCarPlayManager ERROR: Failed to push Now Playing template: %@", error);
            } else {
                NSLog(@"CDVCarPlayManager: Now Playing template displayed successfully");
                // Note: We cannot call presentTemplate with CPNowPlayingTemplate as it's not supported
                // CPNowPlayingTemplate can only be pushed, not presented
            }
        }];
    });
}

- (void)updateNowPlayingTemplate:(NSNotification *)notification {
    // Use a static token to track and prevent recursive calls
    static NSString *currentUpdateToken = nil;
    static NSInteger updateCounter = 0;
    static NSDate *lastUpdateTime = nil;
    
    // Generate a unique token for this update
    NSString *updateToken = [[NSUUID UUID] UUIDString];
    
    // Check if we're already updating
    if (currentUpdateToken != nil) {
        NSLog(@"CDVCarPlayManager: Already updating Now Playing template (token: %@), skipping recursive call", currentUpdateToken);
        return;
    }
    
    // Check if this update is too soon after the last one (throttle updates)
    NSDate *now = [NSDate date];
    if (lastUpdateTime && [now timeIntervalSinceDate:lastUpdateTime] < 0.5) {
        NSLog(@"CDVCarPlayManager: Update requested too soon after previous update, throttling");
        return;
    }
    
    // Set the current update token and timestamp
    currentUpdateToken = updateToken;
    lastUpdateTime = now;
    updateCounter++;
    
    NSLog(@"CDVCarPlayManager: Starting update #%ld with token: %@", (long)updateCounter, updateToken);
    
    @try {
        NSLog(@"CDVCarPlayManager: Received request to update Now Playing template UI");
        
        // Log notification details
        NSLog(@"CDVCarPlayManager: Notification name: %@", notification.name);
        
        NSDictionary *track = notification.userInfo[@"track"];
        NSNumber *isPlaying = notification.userInfo[@"isPlaying"];
        
        NSLog(@"CDVCarPlayManager: Track title: %@, artist: %@, album: %@", 
              track[@"title"], track[@"artist"], track[@"album"]);
        
        if (!track) {
            NSLog(@"CDVCarPlayManager: No track data provided, skipping update");
            return;
        }
        
        NSLog(@"CDVCarPlayManager: Updating now playing template with track: %@", track[@"title"]);
        
        // Get the Now Playing template
        CPNowPlayingTemplate *nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
        
        // Extract track information
        NSString *title = track[@"title"] ?: @"Unknown Title";
        NSString *artist = track[@"artist"] ?: @"Unknown Artist";
        NSString *album = track[@"album"] ?: @"Unknown Album";
        NSString *imageURL = track[@"image"];
        
        // Debug logging
        NSLog(@"CDVCarPlayManager DEBUG: Track data - Title: %@, Artist: %@, Album: %@", title, artist, album);
        
        // Create a fresh dictionary for MPNowPlayingInfoCenter
        NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
        
        // Set basic metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = title;
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist;
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album;
        
        // Add playback information
        if (notification.userInfo[@"duration"]) {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = notification.userInfo[@"duration"];
        }
        
        if (notification.userInfo[@"elapsedTime"]) {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = notification.userInfo[@"elapsedTime"];
        }
        
        // Set playback state
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? @1.0 : @0.0;
        
        // Update the Now Playing Info Center with basic metadata first
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nowPlayingInfo];
    
        // Update the interfaceController if available
        if (self.interfaceController && self.connected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Show the Now Playing template first time only
                static BOOL firstUpdate = YES;
                if (firstUpdate) {
                    firstUpdate = NO;
                    NSLog(@"CDVCarPlayManager: First update - showing Now Playing template");
                    [self showNowPlayingTemplate:nil];
                }
                
                // REMOVED duplicate UI refresh call here to prevent update loops
                // UI refresh will be done either immediately (if no artwork) or after artwork loads
                
                // CRITICAL FIX: Move UI refresh AFTER artwork loading to ensure we only refresh once
                // Only refresh UI immediately if there's no artwork to load
                BOOL hasArtworkToLoad = (imageURL && [imageURL hasPrefix:@"http"]);
                
                if (!hasArtworkToLoad) {
                    // No artwork to load, so refresh UI now
                    if (@available(iOS 14.0, *)) {
                        NSLog(@"CDVCarPlayManager: No artwork to load, refreshing UI immediately");
                        [nowPlayingTemplate updateNowPlayingButtons:@[]];
                        NSLog(@"CDVCarPlayManager: UI refresh completed");
                    }
                }
                
                // Handle artwork loading - only if URL exists and starts with http
                if (hasArtworkToLoad) {
                    NSLog(@"CDVCarPlayManager: Starting artwork load from URL: %@", imageURL);
                    
                    // Use NSURLSession for better control and timeout handling
                    NSURLSession *session = [NSURLSession sharedSession];
                    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:imageURL] 
                                                            cachePolicy:NSURLRequestUseProtocolCachePolicy 
                                                        timeoutInterval:10.0];
                    
                    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        if (error) {
                            NSLog(@"CDVCarPlayManager: Failed to load artwork: %@", error);
                            return;
                        }
                        
                        UIImage *artwork = data ? [UIImage imageWithData:data] : nil;
                        if (!artwork) {
                            NSLog(@"CDVCarPlayManager: Failed to create image from data");
                            return;
                        }
                        
                        NSLog(@"CDVCarPlayManager: Artwork loaded successfully: %@", NSStringFromCGSize(artwork.size));
                        
                        // Create MPMediaItemArtwork
                        MPMediaItemArtwork *mediaArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size 
                                                                                          requestHandler:^UIImage * _Nonnull(CGSize size) {
                            return artwork;
                        }];
                        
                        // Update MPNowPlayingInfoCenter with artwork on main thread
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSLog(@"CDVCarPlayManager: Updating MPNowPlayingInfoCenter with artwork");
                            // Get current info to preserve other metadata
                            NSMutableDictionary *updatedInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
                            if (updatedInfo) {
                                updatedInfo[MPMediaItemPropertyArtwork] = mediaArtwork;
                                [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = updatedInfo;
                                NSLog(@"CDVCarPlayManager: Artwork update complete");
                                
                                // CRITICAL FIX: Only refresh UI once after artwork is loaded
                                if (@available(iOS 14.0, *)) {
                                    NSLog(@"CDVCarPlayManager: Refreshing UI after artwork load");
                                    [nowPlayingTemplate updateNowPlayingButtons:@[]];
                                    NSLog(@"CDVCarPlayManager: UI refresh after artwork completed");
                                }
                            } else {
                                NSLog(@"CDVCarPlayManager: Error - No current info available for artwork update");
                            }
                        });
                    }];
                    
                    [task resume];
                }
            });
            
            NSLog(@"CDVCarPlayManager: Now Playing template update completed for track: %@", track[@"title"]);
        } else {
            NSLog(@"CDVCarPlayManager WARNING: Cannot show Now Playing template - interface controller is nil or not connected");
        }
    } @catch (NSException *exception) {
        NSLog(@"CDVCarPlayManager ERROR: Exception while updating Now Playing template: %@", exception);
    } @finally {
        // Store the token locally to ensure we're resetting the correct one
        NSString *tokenToReset = currentUpdateToken;
        
        // Reset the token to allow future updates - IMPORTANT: This must happen on the main thread
        // and with a slight delay to ensure all pending operations complete
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"CDVCarPlayManager: Resetting update token to allow future updates: %@", tokenToReset);
            
            // Add a small delay to ensure all pending operations are complete
            // This is critical to prevent overlapping updates
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Only reset if the token hasn't changed (another update hasn't started)
                if (currentUpdateToken == tokenToReset) {
                    NSLog(@"CDVCarPlayManager: Update token reset complete for token: %@", tokenToReset);
                    currentUpdateToken = nil;
                } else {
                    NSLog(@"CDVCarPlayManager: Token has changed since reset was scheduled. Current: %@, Was: %@", 
                          currentUpdateToken, tokenToReset);
                }
            });
        });
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