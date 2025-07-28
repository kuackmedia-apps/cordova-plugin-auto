#import "CPNowPlayingTemplate+CDVExtensions.h"
#import <MediaPlayer/MediaPlayer.h>
#import "CDVLogger.h"

@implementation CPNowPlayingTemplate (CDVExtensions)

- (void)cdv_setTitle:(NSString *)title {
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Setting title to %@", title);
    [CDVLogger log:[NSString stringWithFormat:@"CPNowPlayingTemplate+CDVExtensions: Setting title to %@", title]];
    
    // Use MPNowPlayingInfoCenter instead of direct KVC to avoid crashes
    NSMutableDictionary *info = [[[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
    info[MPMediaItemPropertyTitle] = title;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    
    // No template refresh here to prevent update loops
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Title set complete");
}

- (void)cdv_setSubtitle:(NSString *)subtitle {
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Setting subtitle to %@", subtitle);
    [CDVLogger log:[NSString stringWithFormat:@"CPNowPlayingTemplate+CDVExtensions: Setting subtitle to %@", subtitle]];
    
    // Use MPNowPlayingInfoCenter instead of direct KVC to avoid crashes
    NSMutableDictionary *info = [[[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
    info[MPMediaItemPropertyArtist] = subtitle;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    
    // No template refresh here to prevent update loops
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Subtitle set complete");
}

- (void)cdv_setAlbumTitle:(NSString *)albumTitle {
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Setting album title to %@", albumTitle);
    [CDVLogger log:[NSString stringWithFormat:@"CPNowPlayingTemplate+CDVExtensions: Setting album title to %@", albumTitle]];
    
    // Use MPNowPlayingInfoCenter instead of direct KVC to avoid crashes
    NSMutableDictionary *info = [[[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
    info[MPMediaItemPropertyAlbumTitle] = albumTitle;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    
    // No template refresh here to prevent update loops
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Album title set complete");
}

- (void)cdv_setImage:(UIImage *)image {
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Setting image");
    [CDVLogger log:@"CPNowPlayingTemplate+CDVExtensions: Setting image"];
    
    // Use MPNowPlayingInfoCenter instead of direct KVC to avoid crashes
    if (!image) {
        NSLog(@"CPNowPlayingTemplate+CDVExtensions: Image is nil, skipping");
        return;
    }
    
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Image size: %@", NSStringFromCGSize(image.size));
    
    NSMutableDictionary *info = [[[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
    
    // Create MPMediaItemArtwork from the UIImage
    MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size 
                                                              requestHandler:^UIImage * _Nonnull(CGSize size) {
        return image;
    }];
    
    info[MPMediaItemPropertyArtwork] = albumArt;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    
    // No template refresh here to prevent update loops
    NSLog(@"CPNowPlayingTemplate+CDVExtensions: Image set complete");
}

@end
