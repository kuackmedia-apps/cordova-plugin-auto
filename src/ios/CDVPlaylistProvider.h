#import <Foundation/Foundation.h>

@interface CDVPlaylistProvider : NSObject

// Original hardcoded methods (kept for backward compatibility)
+ (NSArray *)hardcodedPlaylists;
+ (NSArray *)tracksForPlaylist:(NSString *)playlistId;

// New methods to load from JSON files
+ (NSArray *)loadPlaylistsFromJSON;
+ (NSArray *)loadTracksForPlaylist:(NSString *)playlistId;
+ (NSArray *)loadNavigationFromJSON;

// Utility methods
+ (id)loadJSONFromFile:(NSString *)filename inDirectory:(NSString *)directory;
+ (NSString *)dataPath;

@end
