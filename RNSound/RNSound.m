#import "RNSound.h"

#if __has_include("RCTUtils.h")
#import "RCTUtils.h"
#else
#import <React/RCTUtils.h>
#endif

@implementation RNSound {
    NSMutableDictionary *_playerPool;
    NSMutableDictionary *_callbackPool;
    NSMutableDictionary *_fadeoutTimers; // 소리 페이드 아웃 시키기
}

@synthesize _key = _key;

- (void)audioSessionChangeObserver:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    AVAudioSessionRouteChangeReason audioSessionRouteChangeReason =
        [userInfo[@"AVAudioSessionRouteChangeReasonKey"] longValue];
    AVAudioSessionInterruptionType audioSessionInterruptionType =
        [userInfo[@"AVAudioSessionInterruptionTypeKey"] longValue];
    AVAudioPlayer *player = [self playerForKey:self._key];
    if (audioSessionInterruptionType == AVAudioSessionInterruptionTypeEnded) {
        if (player && player.isPlaying) {
            [player play];
            [self setOnPlay:YES forPlayerKey:self._key];
        }
    }
    else if (audioSessionRouteChangeReason ==
        AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        if (player) {
            [player pause];
            [self setOnPlay:NO forPlayerKey:self._key];
        }
    }
    else if (audioSessionInterruptionType == AVAudioSessionInterruptionTypeBegan) {
        if (player) {
            [player pause];
            [self setOnPlay:NO forPlayerKey:self._key];
        }
    }
}

- (NSMutableDictionary *)playerPool {
    if (!_playerPool) {
        _playerPool = [NSMutableDictionary new];
    }
    return _playerPool;
}

- (NSMutableDictionary *)callbackPool {
    if (!_callbackPool) {
        _callbackPool = [NSMutableDictionary new];
    }
    return _callbackPool;
}

// kosick
- (NSMutableDictionary *)fadeoutTimers {
    if (!_fadeoutTimers) {
        _fadeoutTimers = [NSMutableDictionary new];
    }
    return _fadeoutTimers;
}

- (AVAudioPlayer *)playerForKey:(nonnull NSNumber *)key {
    return [[self playerPool] objectForKey:key];
}

- (NSNumber *)keyForPlayer:(nonnull AVAudioPlayer *)player {
    return [[[self playerPool] allKeysForObject:player] firstObject];
}

- (RCTResponseSenderBlock)callbackForKey:(nonnull NSNumber *)key {
    return [[self callbackPool] objectForKey:key];
}

- (NSString *)getDirectory:(int)directory {
    return [NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask,
                                                YES) firstObject];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player
                       successfully:(BOOL)flag {
    @synchronized(self) {
        NSNumber *key = [self keyForPlayer:player];
        if (key == nil)
            return;

        [self setOnPlay:NO forPlayerKey:key];
        RCTResponseSenderBlock callback = [self callbackForKey:key];
        if (callback) {
            callback(
                [NSArray arrayWithObjects:[NSNumber numberWithBool:flag], nil]);
            [[self callbackPool] removeObjectForKey:key];
        }
    }
}

// Kosick - 모든 오디오 중지
- (void)_pauseAllPlayers {
  for (NSNumber *key in _playerPool) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player.isPlaying) {
      [player pause];
      [self setOnPlay:NO forPlayerKey:key];
    }
  }
}

// Kosick - 모든 오디오 '조금씩 페이드아웃' 중지
- (void)_pauseFadeoutAll {
  for (NSNumber *key in _playerPool) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player.isPlaying) {
      [self fadeOutAndPausePlayer:player forKey:key];
    }
  }
}

// Kosick - 소리를 조금씩 줄이면서 중지. (페이드아웃)
- (void)fadeOutAndPausePlayer:(AVAudioPlayer *)player forKey:(NSNumber *)key {
  CGFloat fadeOutDuration = 2.0; // Time in seconds for the fade-out effect
  CGFloat fadeOutStep = 0.1;     // how much to decrease the volume at each step
  CGFloat minimumVolumeThreshold = 0.05; // The minimum volume threshold

  // Schedule a timer to gradually decrease the volume
  NSTimer *fadeOutTimer =
      [NSTimer timerWithTimeInterval:fadeOutDuration * fadeOutStep
                              target:self
                            selector:@selector(decreaseVolumeAndCheck:)
                            userInfo:@{
                              @"player" : player,
                              @"key" : key,
                              @"step" : @(fadeOutStep),
                              @"threshold" : @(minimumVolumeThreshold)
                            }
                             repeats:YES];

  // Add the timer to the run loop
  [[NSRunLoop mainRunLoop] addTimer:fadeOutTimer forMode:NSRunLoopCommonModes];
  // Store the timer in the timers dictionary
  [self.fadeoutTimers setObject:fadeOutTimer forKey:key];
}

// Kosick - 페이드아웃 timer 콜백함수
- (void)decreaseVolumeAndCheck:(NSTimer *)timer {
  AVAudioPlayer *player = timer.userInfo[@"player"];
  NSNumber *key = timer.userInfo[@"key"];
  CGFloat fadeOutStep = [timer.userInfo[@"step"] floatValue];
  CGFloat minimumVolumeThreshold = [timer.userInfo[@"threshold"] floatValue];

  if (player.volume > minimumVolumeThreshold) {
    player.volume -= fadeOutStep;
  } else {
    [player pause];
    [self setOnPlay:NO forPlayerKey:key];
    [timer invalidate];
    [self.fadeoutTimers removeObjectForKey:key];
  }
}

// Kosick - timer invalidate (pause 시에 호출)
- (void)_invalidateTimer {
  if (self._timer) {
    [self._timer invalidate];
    self._timer = nil;
  }
}

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents {
    return [NSArray arrayWithObjects:@"onPlayChange", nil];
}

- (NSDictionary *)constantsToExport {
    return [NSDictionary
        dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], @"IsAndroid",
                                     [[NSBundle mainBundle] bundlePath],
                                     @"MainBundlePath",
                                     [self getDirectory:NSDocumentDirectory],
                                     @"NSDocumentDirectory",
                                     [self getDirectory:NSLibraryDirectory],
                                     @"NSLibraryDirectory",
                                     [self getDirectory:NSCachesDirectory],
                                     @"NSCachesDirectory", nil];
}

RCT_EXPORT_METHOD(enable : (BOOL)enabled) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryAmbient error:nil];
    [session setActive:enabled error:nil];
}

RCT_EXPORT_METHOD(setActive : (BOOL)active) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:active error:nil];
}

RCT_EXPORT_METHOD(setMode : (NSString *)modeName) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *mode = nil;

    if ([modeName isEqual:@"Default"]) {
        mode = AVAudioSessionModeDefault;
    } else if ([modeName isEqual:@"VoiceChat"]) {
        mode = AVAudioSessionModeVoiceChat;
    } else if ([modeName isEqual:@"VideoChat"]) {
        mode = AVAudioSessionModeVideoChat;
    } else if ([modeName isEqual:@"GameChat"]) {
        mode = AVAudioSessionModeGameChat;
    } else if ([modeName isEqual:@"VideoRecording"]) {
        mode = AVAudioSessionModeVideoRecording;
    } else if ([modeName isEqual:@"Measurement"]) {
        mode = AVAudioSessionModeMeasurement;
    } else if ([modeName isEqual:@"MoviePlayback"]) {
        mode = AVAudioSessionModeMoviePlayback;
    } else if ([modeName isEqual:@"SpokenAudio"]) {
        mode = AVAudioSessionModeSpokenAudio;
    }

    if (mode) {
        [session setMode:mode error:nil];
    }
}

RCT_EXPORT_METHOD(setCategory
                  : (NSString *)categoryName mixWithOthers
                  : (BOOL)mixWithOthers) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *category = nil;

    if ([categoryName isEqual:@"Ambient"]) {
        category = AVAudioSessionCategoryAmbient;
    } else if ([categoryName isEqual:@"SoloAmbient"]) {
        category = AVAudioSessionCategorySoloAmbient;
    } else if ([categoryName isEqual:@"Playback"]) {
        category = AVAudioSessionCategoryPlayback;
    } else if ([categoryName isEqual:@"Record"]) {
        category = AVAudioSessionCategoryRecord;
    } else if ([categoryName isEqual:@"PlayAndRecord"]) {
        category = AVAudioSessionCategoryPlayAndRecord;
    }
#if TARGET_OS_IOS
    else if ([categoryName isEqual:@"AudioProcessing"]) {
        category = AVAudioSessionCategoryAudioProcessing;
    }
#endif
    else if ([categoryName isEqual:@"MultiRoute"]) {
        category = AVAudioSessionCategoryMultiRoute;
    }

    if (category) {
        if (mixWithOthers) {
            [session setCategory:category
                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                    // kosick) 이거떄문에 background 잘 안돌아서 patch 함. 참고)
                    // https://github.com/zmxv/react-native-sound/issues/788 |
                    // AVAudioSessionCategoryOptionAllowBluetooth
                           error:nil];
        } else {
            [session setCategory:category error:nil];
        }
    }
}

RCT_EXPORT_METHOD(enableInSilenceMode : (BOOL)enabled) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    [session setActive:enabled error:nil];
}

RCT_EXPORT_METHOD(prepare
                  : (NSString *)fileName withKey
                  : (nonnull NSNumber *)key withOptions
                  : (NSDictionary *)options withCallback
                  : (RCTResponseSenderBlock)callback) {
    NSError *error;
    NSURL *fileNameUrl;
    AVAudioPlayer *player;
    NSString* fileNameEscaped = [fileName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    if ([fileNameEscaped hasPrefix:@"http"]) {
        fileNameUrl = [NSURL URLWithString:fileNameEscaped];
        NSData *data = [NSData dataWithContentsOfURL:fileNameUrl];
        player = [[AVAudioPlayer alloc] initWithData:data error:&error];
    } else if ([fileNameEscaped hasPrefix:@"ipod-library://"]) {
        fileNameUrl = [NSURL URLWithString:fileNameEscaped];
        player = [[AVAudioPlayer alloc] initWithContentsOfURL:fileNameUrl
                                                        error:&error];
    } else {
        fileNameUrl = [NSURL URLWithString:fileNameEscaped];
        player = [[AVAudioPlayer alloc] initWithContentsOfURL:fileNameUrl
                                                        error:&error];
    }

    if (player) {
        @synchronized(self) {
            player.delegate = self;
            player.enableRate = YES;
            [player prepareToPlay];
            [[self playerPool] setObject:player forKey:key];
            callback([NSArray
                arrayWithObjects:[NSNull null],
                                 [NSDictionary
                                     dictionaryWithObjectsAndKeys:
                                         [NSNumber
                                             numberWithDouble:player.duration],
                                         @"duration",
                                         [NSNumber numberWithUnsignedInteger:
                                                       player.numberOfChannels],
                                         @"numberOfChannels", nil],
                                 nil]);
        }
    } else {
        callback([NSArray arrayWithObjects:RCTJSErrorFromNSError(error), nil]);
    }
}

RCT_EXPORT_METHOD(play
                  : (nonnull NSNumber *)key withCallback
                  : (RCTResponseSenderBlock)callback) {
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(audioSessionChangeObserver:)
               name:AVAudioSessionRouteChangeNotification
             object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(audioSessionChangeObserver:)
               name:AVAudioSessionInterruptionNotification
             object:[AVAudioSession sharedInstance]];
    self._key = key;
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        [[self callbackPool] setObject:[callback copy] forKey:key];
        [player play];
        [self setOnPlay:YES forPlayerKey:key];
    }
}

// Kosick - 타이머로 일정시간 후에 모든 오디오 FADEOUT 정지
RCT_EXPORT_METHOD(pauseAllPlayersTimer : (nonnull NSNumber *)timerDuration) {
  NSTimeInterval duration = [timerDuration doubleValue];
  self._timer =
      [NSTimer timerWithTimeInterval:duration
                              target:self
                            selector:@selector(_pauseFadeoutAll)
                            // selector:@selector(_pauseAllPlayers) <- 원래는 fadeout 이 아니라 그냥 정지였다.
                            userInfo:nil
                             repeats:NO];
  [[NSRunLoop mainRunLoop] addTimer:self._timer forMode:NSRunLoopCommonModes];
}

// Kosick - 즉시 모든 타이머 Invalidate
RCT_EXPORT_METHOD(invalidateTimer) { [self _invalidateTimer]; }

// Kosick - 즉시 모든 Player pause
RCT_EXPORT_METHOD(pauseAllPlayers) { [self _pauseAllPlayers]; }

// Kosick - 기존 함수인데 setOnPlay 알려주는 방식을 추가함.
RCT_EXPORT_METHOD(pause
                  : (nonnull NSNumber *)key withCallback
                  : (RCTResponseSenderBlock)callback) {

  AVAudioPlayer *player = [self playerForKey:key];
  if (player) {
    if (player.isPlaying) {
      // RCTLogInfo(@"-------key: %@ pause FIRED", key);
      [self setOnPlay:NO forPlayerKey:key]; // 이벤트 단에 알려준다. (Kosick)
    }
    [player pause];
    callback([NSArray array]);
  }
}

RCT_EXPORT_METHOD(stop
                  : (nonnull NSNumber *)key withCallback
                  : (RCTResponseSenderBlock)callback) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        [player stop];
        player.currentTime = 0;
        callback([NSArray array]);
    }
}

RCT_EXPORT_METHOD(release : (nonnull NSNumber *)key) {
    @synchronized(self) {
        AVAudioPlayer *player = [self playerForKey:key];
        if (player) {
            [player stop];
            [[self callbackPool] removeObjectForKey:key];
            [[self playerPool] removeObjectForKey:key];
            NSNotificationCenter *notificationCenter =
                [NSNotificationCenter defaultCenter];
            [notificationCenter removeObserver:self];
        }
    }
}

RCT_EXPORT_METHOD(setVolume
                  : (nonnull NSNumber *)key withValue
                  : (nonnull NSNumber *)value) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        player.volume = [value floatValue];
    }
}

RCT_EXPORT_METHOD(getSystemVolume : (RCTResponseSenderBlock)callback) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    callback(@[ @(session.outputVolume) ]);
}

RCT_EXPORT_METHOD(setPan
                  : (nonnull NSNumber *)key withValue
                  : (nonnull NSNumber *)value) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        player.pan = [value floatValue];
    }
}

RCT_EXPORT_METHOD(setNumberOfLoops
                  : (nonnull NSNumber *)key withValue
                  : (nonnull NSNumber *)value) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        player.numberOfLoops = [value intValue];
    }
}

RCT_EXPORT_METHOD(setSpeed
                  : (nonnull NSNumber *)key withValue
                  : (nonnull NSNumber *)value) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        player.rate = [value floatValue];
    }
}

RCT_EXPORT_METHOD(setCurrentTime
                  : (nonnull NSNumber *)key withValue
                  : (nonnull NSNumber *)value) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        player.currentTime = [value doubleValue];
    }
}

RCT_EXPORT_METHOD(getCurrentTime
                  : (nonnull NSNumber *)key withCallback
                  : (RCTResponseSenderBlock)callback) {
    AVAudioPlayer *player = [self playerForKey:key];
    if (player) {
        callback([NSArray
            arrayWithObjects:[NSNumber numberWithDouble:player.currentTime],
                             [NSNumber numberWithBool:player.isPlaying], nil]);
    } else {
        callback([NSArray arrayWithObjects:[NSNumber numberWithInteger:-1],
                                           [NSNumber numberWithBool:NO], nil]);
    }
}

RCT_EXPORT_METHOD(setSpeakerPhone : (BOOL)on) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (on) {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                                   error:nil];
    } else {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone
                                   error:nil];
    }
    [session setActive:true error:nil];
}

+ (BOOL)requiresMainQueueSetup {
    return YES;
}
- (void)setOnPlay:(BOOL)isPlaying forPlayerKey:(nonnull NSNumber *)playerKey {
    [self
        sendEventWithName:@"onPlayChange"
                     body:[NSDictionary
                              dictionaryWithObjectsAndKeys:
                                  [NSNumber
                                      numberWithBool:isPlaying ? YES : NO],
                                  @"isPlaying", playerKey, @"playerKey", nil]];
}
@end
