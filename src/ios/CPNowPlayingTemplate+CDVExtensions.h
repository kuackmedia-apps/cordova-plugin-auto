#import <CarPlay/CarPlay.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPNowPlayingTemplate (CDVExtensions)

// For iOS versions where these properties aren't available
- (void)cdv_setTitle:(NSString *)title;
- (void)cdv_setSubtitle:(NSString *)subtitle;
- (void)cdv_setAlbumTitle:(NSString *)albumTitle;
- (void)cdv_setImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
