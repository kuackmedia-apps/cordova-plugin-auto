#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CarPlay/CarPlay.h>

@class CDVCarPlayManager;

@interface CDVMusicPlayer : NSObject

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSArray *queue;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, readonly, getter=isPlaying) BOOL isPlaying;
@property (nonatomic, readonly) NSDictionary *currentTrack;

- (instancetype)initWithManager:(CDVCarPlayManager *)manager;
- (void)setNowPlayingTemplate:(CPNowPlayingTemplate *)nowPlayingTemplate;

// Playback control
- (void)play;
- (void)pause;
- (void)togglePlayPause;
- (void)skipToNext;
- (void)skipToPrevious;
- (void)seekToPosition:(double)position;
- (double)currentPlaybackPosition;
- (NSString *)currentPlaybackState;

// Queue management
- (void)updateQueue:(NSArray *)queue;
- (void)reloadQueue;
- (void)updateCurrentTrack;
- (void)cleanup;

// Audio session and observations
- (void)setupAudioSession;
- (void)setupPlayerObservers;
- (void)addObservers;
- (void)setupRemoteCommandCenter;
- (void)registerForAudioInterruptions;
- (void)handleAudioSessionInterruption:(NSNotification *)notification;
- (void)updatePlaybackState:(NSString *)state;
- (void)updateNowPlayingInfo;
- (void)updateNowPlayingInfoIfNeeded;
- (void)loadCurrentTrack;
- (void)nextTrack;
- (void)previousTrack;

// Hardcoded content
- (void)playTrack:(NSDictionary *)track;

@end
