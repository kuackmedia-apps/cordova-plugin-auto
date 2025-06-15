#import "CDVPlaylistProvider.h"

@implementation CDVPlaylistProvider

+ (NSArray *)hardcodedPlaylists {
    return @[
        @{
            @"id": @"playlist_1",
            @"title": @"Featured Tracks",
            @"description": @"Our featured music collection"
        },
        @{
            @"id": @"playlist_2",
            @"title": @"Sample Music",
            @"description": @"Sample tracks for demonstration"
        },
        @{
            @"id": @"playlist_3",
            @"title": @"Favorites",
            @"description": @"Your favorite tracks"
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
