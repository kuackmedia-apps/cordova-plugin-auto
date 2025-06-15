#import "CDVPlaylistProvider.h"

@implementation CDVPlaylistProvider

#pragma mark - JSON File Loading Methods

+ (NSString *)dataPath {
    // Path to the App bundle's data directory
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    return [bundlePath stringByAppendingPathComponent:@"data"];
}

+ (id)loadJSONFromFile:(NSString *)filename inDirectory:(NSString *)directory {
    NSLog(@"📝 CDVPlaylistProvider: Attempting to load file %@ from directory data/%@", filename, directory);
    
    // Listar directorios y archivos disponibles para depuración
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSError *fileError = nil;
    NSArray *bundleContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:&fileError];
    if (fileError) {
        NSLog(@"❌ Error listando bundle: %@", fileError);
    } else {
        NSLog(@"📚 Bundle contents: %@", bundleContents);
        
        // Verificar si existe el directorio data
        NSString *dataPath = [bundlePath stringByAppendingPathComponent:@"data"];
        BOOL isDirectory = NO;
        BOOL dataExists = [[NSFileManager defaultManager] fileExistsAtPath:dataPath isDirectory:&isDirectory];
        
        if (dataExists && isDirectory) {
            NSArray *dataContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dataPath error:&fileError];
            if (fileError) {
                NSLog(@"❌ Error listando data: %@", fileError);
            } else {
                NSLog(@"📚 Data contents: %@", dataContents);
                
                // Verificar la carpeta navigation
                NSString *navPath = [dataPath stringByAppendingPathComponent:directory];
                BOOL navExists = [[NSFileManager defaultManager] fileExistsAtPath:navPath isDirectory:&isDirectory];
                
                if (navExists && isDirectory) {
                    NSArray *navContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:navPath error:&fileError];
                    if (fileError) {
                        NSLog(@"❌ Error listando navigation: %@", fileError);
                    } else {
                        NSLog(@"📚 Navigation contents: %@", navContents);
                    }
                } else {
                    NSLog(@"❌ Directorio %@ no existe en data", directory);
                }
            }
        } else {
            NSLog(@"❌ Directorio data no existe!");
        }
    }
    
    // Try multiple path formats to find the file
    NSString *path = nil;
    
    // First try: data/directory/filename (no extension)
    NSString *path1 = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:[NSString stringWithFormat:@"data/%@", directory]];
    NSLog(@"🔍 Trying path 1: data/%@/%@", directory, filename);
    if (path1) {
        path = path1;
        NSLog(@"✅ Found at path 1!");
    }
    
    if (!path) {
        // Second try: data/directory/filename.json
        NSString *path2 = [[NSBundle mainBundle] pathForResource:filename ofType:@"json" inDirectory:[NSString stringWithFormat:@"data/%@", directory]];
        NSLog(@"🔍 Trying path 2: data/%@/%@.json", directory, filename);
        if (path2) {
            path = path2;
            NSLog(@"✅ Found at path 2!");
        }
    }
    
    if (!path) {
        // Third try: directory/filename (no extension)
        NSString *path3 = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:directory];
        NSLog(@"🔍 Trying path 3: %@/%@", directory, filename);
        if (path3) {
            path = path3;
            NSLog(@"✅ Found at path 3!");
        }
    }
    
    if (!path) {
        // Fourth try: directory/filename.json
        NSString *path4 = [[NSBundle mainBundle] pathForResource:filename ofType:@"json" inDirectory:directory];
        NSLog(@"🔍 Trying path 4: %@/%@.json", directory, filename);
        if (path4) {
            path = path4;
            NSLog(@"✅ Found at path 4!");
        }
    }
    
    if (!path) {
        // Last attempt: try relative path
        NSString *path5 = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
        NSLog(@"🔍 Trying path 5: %@", filename);
        if (path5) {
            path = path5;
            NSLog(@"✅ Found at path 5!");
        }
    }
    
    if (!path) {
        NSLog(@"❌ CDVPlaylistProvider ERROR: Could not find file %@ in any location", filename);
        return nil;
    }
    
    NSLog(@"🍿 CDVPlaylistProvider: Found file at path: %@", path);
    
    NSError *error = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:path options:0 error:&error];
    
    if (!jsonData) {
        NSLog(@"❌ CDVPlaylistProvider ERROR: Failed to load JSON file %@: %@", path, error);
        return nil;
    }
    
    // Log the first 100 characters to verify content
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *preview = [jsonStr length] > 100 ? [NSString stringWithFormat:@"%@...",[jsonStr substringToIndex:100]] : jsonStr;
    NSLog(@"📄 JSON Content Preview: %@", preview);
    
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (!jsonObject) {
        NSLog(@"❌ CDVPlaylistProvider ERROR: Failed to parse JSON: %@", error);
        return nil;
    }
    
    NSLog(@"✅ Successfully parsed JSON object type: %@", NSStringFromClass([jsonObject class]));
    
    return jsonObject;
}

+ (NSArray *)loadPlaylistsFromJSON {
    NSLog(@"🔄 CDVPlaylistProvider: loadPlaylistsFromJSON starting...");
    
    // Load the AUTO_NAVIGATION_LIBRARY file which contains playlists
    NSLog(@"🔍 CDVPlaylistProvider: Attempting to load AUTO_NAVIGATION_LIBRARY");
    id libraryContent = [self loadJSONFromFile:@"AUTO_NAVIGATION_LIBRARY" inDirectory:@"navigation"];
    
    if (!libraryContent || ![libraryContent isKindOfClass:[NSArray class]]) {
        NSLog(@"⚠️ CDVPlaylistProvider WARNING: Could not load playlists from AUTO_NAVIGATION_LIBRARY, falling back to hardcoded playlists");
        return [self hardcodedPlaylists];
    }
    
    // Find the "Playlists" section in the library content
    NSDictionary *playlistSection = nil;
    for (NSDictionary *section in libraryContent) {
        if ([section[@"text"] isEqualToString:@"Playlists"]) {
            playlistSection = section;
            break;
        }
    }
    
    if (!playlistSection || ![playlistSection[@"items"] isKindOfClass:[NSArray class]]) {
        NSLog(@"CDVPlaylistProvider WARNING: No playlists section found in AUTO_NAVIGATION_LIBRARY, falling back to hardcoded playlists");
        return [self hardcodedPlaylists];
    }
    
    NSArray *playlistItems = playlistSection[@"items"];
    NSMutableArray *formattedPlaylists = [NSMutableArray array];
    
    // Convert each playlist to the expected format
    for (NSDictionary *playlist in playlistItems) {
        NSMutableDictionary *formattedPlaylist = [NSMutableDictionary dictionary];
        formattedPlaylist[@"id"] = [NSString stringWithFormat:@"%@", playlist[@"id"]];
        formattedPlaylist[@"title"] = playlist[@"name"] ?: @"Unknown Playlist";
        
        // Extract description from the playlist or use a default
        if (playlist[@"description"]) {
            formattedPlaylist[@"description"] = playlist[@"description"];
        } else {
            formattedPlaylist[@"description"] = [NSString stringWithFormat:@"%@ playlist", playlist[@"name"]];
        }
        
        [formattedPlaylists addObject:formattedPlaylist];
    }
    
    NSLog(@"CDVPlaylistProvider: Successfully loaded %lu playlists from AUTO_NAVIGATION_LIBRARY", (unsigned long)formattedPlaylists.count);
    
    if (formattedPlaylists.count == 0) {
        NSLog(@"CDVPlaylistProvider WARNING: No playlists found in AUTO_NAVIGATION_LIBRARY, falling back to hardcoded playlists");
        return [self hardcodedPlaylists];
    }
    
    return formattedPlaylists;
}

+ (NSArray *)loadTracksForPlaylist:(NSString *)playlistId {
    // For any playlist, load tracks from QUEUE_ITEMS_KEY
    NSArray *tracks = [self loadJSONFromFile:@"QUEUE_ITEMS_KEY" inDirectory:@"navigation"];
    
    if (!tracks) {
        NSLog(@"CDVPlaylistProvider WARNING: Could not load tracks from QUEUE_ITEMS_KEY, falling back to hardcoded tracks");
        return [self tracksForPlaylist:playlistId];
    }
    
    // Process tracks to ensure they have all required fields
    NSMutableArray *processedTracks = [NSMutableArray array];
    
    for (NSDictionary *trackData in tracks) {
        // Extract track data
        NSDictionary *data = trackData[@"data"] ?: trackData; // Handle if track is wrapped in a "data" field
        
        // Create a standardized track dictionary with required fields
        NSMutableDictionary *track = [NSMutableDictionary dictionary];
        
        // Map the data to our expected format
        track[@"id"] = [NSString stringWithFormat:@"%@", data[@"id"] ?: @"unknown"];
        track[@"title"] = data[@"title"] ?: data[@"name"] ?: @"Unknown Track";
        track[@"artist"] = data[@"artistName"] ?: data[@"artist"] ?: @"Unknown Artist";
        
        // Extract album info
        if (data[@"album"]) {
            // If album is a dictionary
            if ([data[@"album"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *albumDict = data[@"album"];
                track[@"album"] = albumDict[@"title"] ?: albumDict[@"name"] ?: @"Unknown Album";
            } else {
                // If album is a string
                track[@"album"] = data[@"album"];
            }
        } else {
            track[@"album"] = @"Unknown Album";
        }
        
        // Extract image/artwork URL
        if (data[@"images"] && [data[@"images"] isKindOfClass:[NSArray class]] && [data[@"images"] count] > 0) {
            // If images is an array of dictionaries with URL
            NSDictionary *firstImage = data[@"images"][0];
            track[@"image"] = firstImage[@"url"];
        } else if (data[@"image"]) {
            // Direct image field
            track[@"image"] = data[@"image"];
        }
        
        // Add source/URL
        track[@"source"] = data[@"source"] ?: data[@"url"] ?: @"";
        
        // Add duration if available
        if (data[@"duration"]) {
            track[@"duration"] = data[@"duration"];
        } else if (data[@"length"]) {
            // Convert format like "00:03:45" to milliseconds
            NSString *length = data[@"length"];
            NSArray *components = [length componentsSeparatedByString:@":"];
            NSInteger hours = 0, minutes = 0, seconds = 0;
            
            if (components.count == 3) {
                hours = [components[0] integerValue];
                minutes = [components[1] integerValue];
                seconds = [components[2] integerValue];
            } else if (components.count == 2) {
                minutes = [components[0] integerValue];
                seconds = [components[1] integerValue];
            }
            
            NSInteger totalMs = ((hours * 60 * 60) + (minutes * 60) + seconds) * 1000;
            track[@"duration"] = @(totalMs);
        }
        
        [processedTracks addObject:track];
    }
    
    NSLog(@"CDVPlaylistProvider: Successfully processed %lu tracks from JSON", (unsigned long)processedTracks.count);
    return processedTracks;
}

+ (NSArray *)loadNavigationFromJSON {
    // Define emergency fallback navigation so we have something
    NSArray *emergencyNavigation = @[
        @{
            @"icon": @"img/auto-library.png",
            @"text": @"Biblioteca",
            @"fileName": @"AUTO_NAVIGATION_LIBRARY"
        },
        @{
            @"icon": @"img/auto-recent.png",
            @"text": @"Recientes",
            @"fileName": @"RECENT_LISTENED"
        },
        @{
            @"icon": @"img/auto-explorer.png",
            @"text": @"Explorar",
            @"fileName": @"AUTO_NAVIGATION_EXPLORER"
        }
    ];
    
    NSLog(@"CDVPlaylistProvider: FORCED USING EMERGENCY NAVIGATION STRUCTURE");
    return emergencyNavigation;
    
    // The code below is commented out since we're using the emergency navigation directly
    /*
    // Log all important paths to help diagnose file loading issues
    NSBundle *bundle = [NSBundle mainBundle];
    NSLog(@"CDVPlaylistProvider: Bundle path: %@", bundle.bundlePath);
    NSLog(@"CDVPlaylistProvider: Resource path: %@", bundle.resourcePath);
    
    // Try multiple ways to find and load the AUTO_NAVIGATION file
    NSString *resourcePath = bundle.resourcePath;
    NSString *dataNavigationPath = [resourcePath stringByAppendingPathComponent:@"data/navigation"];
    NSString *autoNavPath = [dataNavigationPath stringByAppendingPathComponent:@"AUTO_NAVIGATION"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSLog(@"CDVPlaylistProvider: Checking if file exists at: %@", autoNavPath);
    BOOL autoNavExists = [fileManager fileExistsAtPath:autoNavPath];
    
    // If file exists, try to load and parse it
    if (autoNavExists) {
        NSLog(@"CDVPlaylistProvider: AUTO_NAVIGATION file exists!");
        NSError *error = nil;
        NSData *jsonData = [NSData dataWithContentsOfFile:autoNavPath options:0 error:&error];
        
        if (jsonData) {
            NSLog(@"CDVPlaylistProvider: Successfully loaded AUTO_NAVIGATION data, bytes: %lu", (unsigned long)[jsonData length]);
            id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            if (json && [json isKindOfClass:[NSArray class]]) {
                NSArray *navArray = (NSArray *)json;
                NSLog(@"CDVPlaylistProvider: Successfully parsed AUTO_NAVIGATION as array with %lu items", (unsigned long)[navArray count]);
                if ([navArray count] > 0) {
                    return navArray;
                }
            } else {
                NSLog(@"CDVPlaylistProvider ERROR: Failed to parse AUTO_NAVIGATION as array: %@", error);
            }
        } else {
            NSLog(@"CDVPlaylistProvider ERROR: Failed to load AUTO_NAVIGATION data: %@", error);
        }
    } else {
        NSLog(@"CDVPlaylistProvider: AUTO_NAVIGATION file does not exist at path");
    }
    
    // Try the standard JSON loading method as a fallback
    NSLog(@"CDVPlaylistProvider: Trying standard loadJSONFromFile method");
    id navigationJSON = [self loadJSONFromFile:@"AUTO_NAVIGATION" inDirectory:@"navigation"];
    
    if (navigationJSON) {
        NSLog(@"CDVPlaylistProvider: Standard loading worked! Type: %@", NSStringFromClass([navigationJSON class]));
        
        // Handle different potential formats
        NSArray *navigationItems = nil;
        
        if ([navigationJSON isKindOfClass:[NSArray class]]) {
            navigationItems = (NSArray *)navigationJSON;
            if ([navigationItems count] > 0) {
                NSLog(@"CDVPlaylistProvider: Returning navigation array with %lu items", (unsigned long)[navigationItems count]);
                return navigationItems;
            }
        } else if ([navigationJSON isKindOfClass:[NSDictionary class]]) {
            NSDictionary *navDict = (NSDictionary *)navigationJSON;
            NSLog(@"CDVPlaylistProvider: AUTO_NAVIGATION is a dictionary with keys: %@", [navDict allKeys]);
            
            // Look for array fields
            for (NSString *key in [navDict allKeys]) {
                if ([navDict[key] isKindOfClass:[NSArray class]]) {
                    navigationItems = navDict[key];
                    NSLog(@"CDVPlaylistProvider: Found navigation items array in key: %@", key);
                    break;
                }
            }
            
            if (navigationItems && navigationItems.count > 0) {
                NSLog(@"CDVPlaylistProvider: Found navigation items from dictionary: %@", navigationItems);
                return navigationItems;
            }
        }
    }
    */
    
    // If all attempts fail, return the emergency navigation structure
    NSLog(@"CDVPlaylistProvider: Returning emergency navigation structure");
    return emergencyNavigation;
}

+ (NSArray *)hardcodedPlaylists {
    // Try to load from AUTO_NAVIGATION_LIBRARY first
    id libraryContent = [self loadJSONFromFile:@"AUTO_NAVIGATION_LIBRARY" inDirectory:@"navigation"];
    
    if (libraryContent && [libraryContent isKindOfClass:[NSArray class]]) {
        // Find the "Playlists" section in the library content
        NSDictionary *playlistSection = nil;
        for (NSDictionary *section in libraryContent) {
            if ([section[@"text"] isEqualToString:@"Playlists"]) {
                playlistSection = section;
                break;
            }
        }
        
        if (playlistSection && [playlistSection[@"items"] isKindOfClass:[NSArray class]]) {
            NSArray *playlistItems = playlistSection[@"items"];
            NSMutableArray *formattedPlaylists = [NSMutableArray array];
            
            // Convert each playlist to the expected format
            for (NSDictionary *playlist in playlistItems) {
                NSMutableDictionary *formattedPlaylist = [NSMutableDictionary dictionary];
                formattedPlaylist[@"id"] = [NSString stringWithFormat:@"%@", playlist[@"id"]];
                formattedPlaylist[@"title"] = playlist[@"name"] ?: @"Unknown Playlist";
                
                // Extract description from the playlist or use a default
                if (playlist[@"description"]) {
                    formattedPlaylist[@"description"] = playlist[@"description"];
                } else {
                    formattedPlaylist[@"description"] = [NSString stringWithFormat:@"%@ playlist", playlist[@"name"]];
                }
                
                [formattedPlaylists addObject:formattedPlaylist];
            }
            
            NSLog(@"CDVPlaylistProvider: Successfully loaded %lu playlists from AUTO_NAVIGATION_LIBRARY", (unsigned long)formattedPlaylists.count);
            
            if (formattedPlaylists.count > 0) {
                return formattedPlaylists;
            }
        }
    }
    
    // Fall back to these default playlists only if nothing can be loaded from files
    NSLog(@"CDVPlaylistProvider WARNING: Using fallback hardcoded playlists");
    return @[
        @{
            @"id": @"playlist_default_1",
            @"title": @"Default Music",
            @"description": @"Default music collection"
        }
    ];
}

+ (NSArray *)tracksForPlaylist:(NSString *)playlistId {
    // For this implementation, all playlists will contain multiple tracks
    // In a real implementation, you would have different tracks for each playlist
    
    // Define sample track URLs
    NSString *sampleTrack1Url = @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3";
    NSString *sampleTrack2Url = @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3";
    NSString *sampleTrack3Url = @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3";
    
    NSMutableArray *tracks = [NSMutableArray array];
    
    // Create multiple tracks with full metadata
    NSDictionary *track1 = @{
        @"id": @"track_1",
        @"title": @"Ambient Melody",
        @"artist": @"T. Schürger",
        @"album": @"SoundHelix Collection",
        @"source": sampleTrack1Url,
        @"image": @"https://picsum.photos/id/26/600/600", // Random image from Lorem Picsum
        @"duration": @(372000) // 6:12 in milliseconds
    };
    
    NSDictionary *track2 = @{
        @"id": @"track_2",
        @"title": @"Electronic Journey",
        @"artist": @"Audio Artist",
        @"album": @"Demo Tracks",
        @"source": sampleTrack2Url,
        @"image": @"https://picsum.photos/id/39/600/600", // Different random image
        @"duration": @(245000) // 4:05 in milliseconds
    };
    
    NSDictionary *track3 = @{
        @"id": @"track_3",
        @"title": @"Relaxing Tones",
        @"artist": @"Sound Creator",
        @"album": @"Calming Collection",
        @"source": sampleTrack3Url,
        @"image": @"https://picsum.photos/id/24/600/600", // Another random image
        @"duration": @(193000) // 3:13 in milliseconds
    };
    
    // Add all tracks to the array
    [tracks addObject:track1];
    [tracks addObject:track2];
    [tracks addObject:track3];
    
    // Log track information for debugging
    NSLog(@"CDVPlaylistProvider: Returning %lu tracks for playlist %@", (unsigned long)tracks.count, playlistId);
    for (NSDictionary *track in tracks) {
        NSLog(@"CDVPlaylistProvider: Track details - Title: %@, Artist: %@, Album: %@", 
              track[@"title"], track[@"artist"], track[@"album"]);
    }
    
    return [NSArray arrayWithArray:tracks];
}

@end
