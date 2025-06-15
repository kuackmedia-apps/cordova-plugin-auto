#import <Foundation/Foundation.h>
#import <CarPlay/CarPlay.h>
#import "CDVMusicPlayer.h"

@class CDVAutoMusicPlugin;

@interface CDVCarPlayManager : NSObject <CPTemplateApplicationSceneDelegate>

@property (nonatomic, strong) CDVMusicPlayer *musicPlayer;
@property (nonatomic, strong) CPInterfaceController *interfaceController;
@property (nonatomic, assign) BOOL connected;

- (instancetype)initWithPlugin:(CDVAutoMusicPlugin *)plugin;
- (BOOL)isConnected;

@end
