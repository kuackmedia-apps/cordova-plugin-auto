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
    NSLog(@"📚 Bundle path: %@", bundlePath);
    
    NSError *fileError = nil;
    NSArray *bundleContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:&fileError];
    if (fileError) {
        NSLog(@"❌ Error listando bundle: %@", fileError);
    } else {
        NSLog(@"📚 Bundle contents: %@", bundleContents);
    }
    
    // Verificar si existe el directorio App/data
    NSString *appPath = [bundlePath stringByAppendingPathComponent:@"App"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
        NSLog(@"✅ App directory exists: %@", appPath);
        NSArray *appContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:&fileError];
        NSLog(@"📚 App contents: %@", appContents);
        
        NSString *appDataPath = [appPath stringByAppendingPathComponent:@"data"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:appDataPath]) {
            NSLog(@"✅ App/data directory exists: %@", appDataPath);
            NSArray *dataContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appDataPath error:&fileError];
            NSLog(@"📚 App/data contents: %@", dataContents);
            
            // Verificar si existe la carpeta navigation dentro de App/data
            NSString *appNavPath = [appDataPath stringByAppendingPathComponent:directory];
            if ([[NSFileManager defaultManager] fileExistsAtPath:appNavPath]) {
                NSLog(@"✅ App/data/%@ directory exists: %@", directory, appNavPath);
                NSArray *navContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appNavPath error:&fileError];
                NSLog(@"📚 App/data/%@ contents: %@", directory, navContents);
            }
        }
    }
    
    // Verificar si existe el directorio data en la raiz
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
                    
                    // Buscar archivo especifico
                    for (NSString *file in navContents) {
                        if ([file isEqualToString:filename] || [file isEqualToString:[NSString stringWithFormat:@"%@.json", filename]]) {
                            NSString *fullPath = [navPath stringByAppendingPathComponent:file];
                            NSLog(@"✅ FOUND EXACT FILE: %@", fullPath);
                        }
                    }
                }
            } else {
                NSLog(@"❌ Directorio %@ no existe en data", directory);
            }
        }
    } else {
        NSLog(@"❌ Directorio data no existe!");
    }
    
    // Try multiple path formats to find the file
    NSString *path = nil;
    
    // NEW PATH: public/data/directory/filename
    NSString *pathPublic = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:[NSString stringWithFormat:@"public/data/%@", directory]];
    NSLog(@"🔍 Trying public path: public/data/%@/%@", directory, filename);
    if (pathPublic) {
        path = pathPublic;
        NSLog(@"✅ Found at public path!");
    }
    
    // NEW PATH: public/data/directory/filename.json
    if (!path) {
        NSString *pathPublicJson = [[NSBundle mainBundle] pathForResource:filename ofType:@"json" inDirectory:[NSString stringWithFormat:@"public/data/%@", directory]];
        NSLog(@"🔍 Trying public path with json: public/data/%@/%@.json", directory, filename);
        if (pathPublicJson) {
            path = pathPublicJson;
            NSLog(@"✅ Found at public path with json!");
        }
    }
    
    // App/data/directory/filename
    if (!path) {
        NSString *pathApp = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:[NSString stringWithFormat:@"App/data/%@", directory]];
        NSLog(@"🔍 Trying App path: App/data/%@/%@", directory, filename);
        if (pathApp) {
            path = pathApp;
            NSLog(@"✅ Found at App path!");
        }
    }
    
    // App/data/directory/filename.json
    if (!path) {
        NSString *pathAppJson = [[NSBundle mainBundle] pathForResource:filename ofType:@"json" inDirectory:[NSString stringWithFormat:@"App/data/%@", directory]];
        NSLog(@"🔍 Trying App path with json: App/data/%@/%@.json", directory, filename);
        if (pathAppJson) {
            path = pathAppJson;
            NSLog(@"✅ Found at App path with json!");
        }
    }
    
    // NEW PATH: App/App/data/directory/filename (no extension)
    if (!path) {
        NSString *pathAppApp = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:[NSString stringWithFormat:@"App/App/data/%@", directory]];
        NSLog(@"🔍 Trying App/App path: App/App/data/%@/%@", directory, filename);
        if (pathAppApp) {
            path = pathAppApp;
            NSLog(@"✅ Found at App/App path!");
        }
    }
    
    // NEW PATH: App/App/data/directory/filename.json
    if (!path) {
        NSString *pathAppAppJson = [[NSBundle mainBundle] pathForResource:filename ofType:@"json" inDirectory:[NSString stringWithFormat:@"App/App/data/%@", directory]];
        NSLog(@"🔍 Trying App/App path with json: App/App/data/%@/%@.json", directory, filename);
        if (pathAppAppJson) {
            path = pathAppAppJson;
            NSLog(@"✅ Found at App/App path with json!");
        }
    }
    
    // First try: data/directory/filename (no extension)
    if (!path) {
        NSString *path1 = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:[NSString stringWithFormat:@"data/%@", directory]];
        NSLog(@"🔍 Trying path 1: data/%@/%@", directory, filename);
        if (path1) {
            path = path1;
            NSLog(@"✅ Found at path 1!");
        }
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
        
        // ÚLTIMA OPORTUNIDAD - Verificar si existe una copia directa en App/data
        NSString *lastChance = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:@"App/data"];
        if (!lastChance) {
            lastChance = [[NSBundle mainBundle] pathForResource:filename ofType:@"json" inDirectory:@"App/data"];
        }
        
        if (lastChance) {
            NSLog(@"🔥 FOUND FILE IN ROOT APP/DATA: %@", lastChance);
            path = lastChance;
        } else {
            NSLog(@"💥 No se encontró el archivo en ninguna ubicación posible");
            return nil;
        }
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
    
    // Intentar analizar el JSON
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingAllowFragments error:&error];
    
    if (!jsonObject) {
        NSLog(@"❌ CDVPlaylistProvider ERROR: Failed to parse JSON: %@", error);
        
        // Intento de recuperación para ciertos formatos incorrectos
        // Eliminar caracteres no válidos y reintentar
        NSMutableData *cleanData = [NSMutableData data];
        const char *bytes = [jsonData bytes];
        for (NSUInteger i = 0; i < [jsonData length]; i++) {
            char c = bytes[i];
            // Eliminar caracteres de control excepto saltos de línea y tabulaciones
            if (c >= 32 || c == 9 || c == 10 || c == 13) {
                [cleanData appendBytes:&c length:1];
            }
        }
        
        jsonObject = [NSJSONSerialization JSONObjectWithData:cleanData options:NSJSONReadingAllowFragments error:&error];
        if (!jsonObject) {
            NSLog(@"❌ CDVPlaylistProvider ERROR: Segundo intento fallido de parseo: %@", error);
            return nil;
        }
        NSLog(@"⚠️ Recuperación exitosa después de limpiar datos");
    }
    
    NSLog(@"✅ Successfully parsed JSON object type: %@", NSStringFromClass([jsonObject class]));
    
    if ([jsonObject isKindOfClass:[NSArray class]]) {
        NSLog(@"✅ Array with %lu items", (unsigned long)[(NSArray *)jsonObject count]);
    } else if ([jsonObject isKindOfClass:[NSDictionary class]]) {
        NSLog(@"✅ Dictionary with %lu keys: %@", (unsigned long)[(NSDictionary *)jsonObject count], [[(NSDictionary *)jsonObject allKeys] componentsJoinedByString:@", "]);
    }
    
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
    
    NSLog(@"CDVPlaylistProvider: Successfully loaded %lu tracks from QUEUE_ITEMS_KEY", (unsigned long)tracks.count);
    
    // Process tracks to ensure they have all required fields
    NSMutableArray *processedTracks = [NSMutableArray array];
    
    for (NSDictionary *trackData in tracks) {
        // Extract track data
        NSDictionary *data = trackData[@"data"] ?: trackData; // Handle if track is wrapped in a "data" field
        
        // Create a standardized track dictionary with required fields
        NSMutableDictionary *track = [NSMutableDictionary dictionary];
        
        // Map the data to our expected format
        track[@"id"] = [NSString stringWithFormat:@"%@", data[@"id"] ?: @"unknown"];
        track[@"title"] = data[@"name"] ?: data[@"title"] ?: @"Unknown Track";
        
        // Extract artist info from artists array
        if (data[@"artists"] && [data[@"artists"] isKindOfClass:[NSArray class]] && [data[@"artists"] count] > 0) {
            // Get the first artist's name
            NSDictionary *firstArtist = data[@"artists"][0];
            track[@"artist"] = firstArtist[@"name"] ?: @"Unknown Artist";
            
            // If there are multiple artists, combine their names
            if ([data[@"artists"] count] > 1) {
                NSMutableString *artistNames = [NSMutableString stringWithString:track[@"artist"]];
                
                for (NSUInteger i = 1; i < [data[@"artists"] count]; i++) {
                    NSDictionary *artist = data[@"artists"][i];
                    [artistNames appendFormat:@", %@", artist[@"name"] ?: @"Unknown"];
                }
                
                track[@"artist"] = artistNames;
            }
        } else {
            track[@"artist"] = data[@"artistName"] ?: data[@"artist"] ?: @"Unknown Artist";
        }
        
        // Extract album info
        if (data[@"album"]) {
            // If album is a dictionary
            if ([data[@"album"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *albumDict = data[@"album"];
                track[@"album"] = albumDict[@"title"] ?: albumDict[@"name"] ?: @"Unknown Album";
                
                // Extract album artwork if available
                if (albumDict[@"images"] && [albumDict[@"images"] isKindOfClass:[NSArray class]] && [albumDict[@"images"] count] > 0) {
                    // Get the largest image available (usually the last one)
                    NSArray *albumImages = albumDict[@"images"];
                    NSDictionary *largestImage = albumImages[[albumImages count] - 1]; // Get the last image (usually largest)
                    track[@"image"] = largestImage[@"url"];
                }
            } else {
                // If album is a string
                track[@"album"] = data[@"album"];
            }
        } else {
            track[@"album"] = @"Unknown Album";
        }
        
        // Extract image/artwork URL if not already set from album
        if (!track[@"image"]) {
            if (data[@"images"] && [data[@"images"] isKindOfClass:[NSArray class]] && [data[@"images"] count] > 0) {
                // If images is an array of dictionaries with URL
                NSArray *images = data[@"images"];
                NSDictionary *largestImage = images[[images count] - 1]; // Get the last image (usually largest)
                track[@"image"] = largestImage[@"url"];
            } else if (data[@"image"]) {
                // Direct image field
                track[@"image"] = data[@"image"];
            }
        }
        
        // Add source/URL - for testing, we'll use a sample URL since the JSON doesn't contain actual audio URLs
        // In a real app, you would extract this from your JSON or use a streaming URL based on the track ID
        if (data[@"audioId"]) {
            // If there's an audioId, we can construct a URL to the audio file
            track[@"source"] = [NSString stringWithFormat:@"https://audio.example.com/%@.mp3", data[@"audioId"]];
        } else {
            // Fallback to sample URLs for testing
            NSArray *sampleURLs = @[
                @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
                @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3",
                @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3"
            ];
            
            // Use a consistent URL based on the track ID to ensure the same track always gets the same URL
            NSInteger trackIdValue = [track[@"id"] integerValue];
            NSInteger urlIndex = trackIdValue % [sampleURLs count];
            track[@"source"] = sampleURLs[urlIndex];
        }
        
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
    NSLog(@"CDVPlaylistProvider: Attempting to load AUTO_NAVIGATION JSON file...");
    
    // Define the emergency navigation structure to be used if no JSON is found
    NSArray *emergencyNavigation = @[
        @{
            @"icon": @"music.note.list",
            @"sfSymbol": @"music.note.list",
            @"text": @"Biblioteca",
            @"fileName": @"AUTO_NAVIGATION_LIBRARY"
        },
        @{
            @"icon": @"clock",
            @"sfSymbol": @"clock",
            @"text": @"Recientes",
            @"fileName": @"RECENT_LISTENED"
        },
        @{
            @"icon": @"magnifyingglass",
            @"sfSymbol": @"magnifyingglass",
            @"text": @"Explorar",
            @"fileName": @"AUTO_NAVIGATION_EXPLORER"
        }
    ];
    
    // Try loading from navigation directory
    id jsonObject = [self loadJSONFromFile:@"AUTO_NAVIGATION" inDirectory:@"navigation"];
    
    // If that fails, try with .json extension
    if (!jsonObject) {
        jsonObject = [self loadJSONFromFile:@"AUTO_NAVIGATION.json" inDirectory:@"navigation"];
        NSLog(@"CDVPlaylistProvider: Tried loading with .json extension: %@", jsonObject ? @"success" : @"failed");
    }
    
    // If still not found, log what files are available in the bundle
    if (!jsonObject) {
        NSLog(@"CDVPlaylistProvider: Still can't find AUTO_NAVIGATION - logging bundle info");
        
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSLog(@"CDVPlaylistProvider: Bundle path: %@", [mainBundle bundlePath]);
        NSLog(@"CDVPlaylistProvider: Resource path: %@", [mainBundle resourcePath]);
        
        // Log what's in the bundle root
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        NSArray *items = [fileManager contentsOfDirectoryAtPath:[mainBundle resourcePath] error:&error];
        if (items) {
            NSLog(@"CDVPlaylistProvider: Bundle contains %lu items at root", (unsigned long)items.count);
            for (NSString *item in items) {
                NSLog(@"CDVPlaylistProvider: - %@", item);
            }
        } else {
            NSLog(@"CDVPlaylistProvider: Failed to list bundle contents: %@", error);
        }
    }
    
    // Convert loaded JSON into navigation items array
    NSMutableArray *navigationItems = [NSMutableArray array];
    
    if (jsonObject) {
        // Handle different JSON formats (array or dictionary with "items" key)
        if ([jsonObject isKindOfClass:[NSArray class]]) {
            navigationItems = [(NSArray *)jsonObject mutableCopy];
            NSLog(@"CDVPlaylistProvider: Loaded navigation items from array, count: %lu", (unsigned long)[navigationItems count]);
        } else if ([jsonObject isKindOfClass:[NSDictionary class]] && [(NSDictionary *)jsonObject[@"items"] isKindOfClass:[NSArray class]]) {
            navigationItems = [(NSDictionary *)jsonObject[@"items"] mutableCopy];
            NSLog(@"CDVPlaylistProvider: Loaded navigation items from dictionary, count: %lu", (unsigned long)[navigationItems count]);
        } else {
            NSLog(@"CDVPlaylistProvider: JSON object has unexpected format: %@", [jsonObject class]);
        }
    } else {
        NSLog(@"CDVPlaylistProvider: No JSON object could be loaded, using emergency navigation");
    }
    
    // Return the loaded navigation items if we have them, otherwise use emergency navigation
    if (navigationItems && navigationItems.count > 0) {
        NSLog(@"CDVPlaylistProvider: Returning loaded navigation with %lu items", (unsigned long)navigationItems.count);
        return navigationItems;
    }
    
    // If all attempts fail, return the emergency navigation structure
    NSLog(@"CDVPlaylistProvider: Falling back to emergency navigation structure");
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
