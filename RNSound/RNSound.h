#if __has_include(<React/RCTBridgeModule.h>)
#import <React/RCTBridgeModule.h>
#else
#import "RCTBridgeModule.h"
#endif

#import <AVFoundation/AVFoundation.h>

#if __has_include(<React/RCTEventEmitter.h>)
#import <React/RCTEventEmitter.h>
#else
#import "RCTEventEmitter.h"
#endif

@interface RNSound : RCTEventEmitter <RCTBridgeModule, AVAudioPlayerDelegate>
@property (nonatomic, weak) NSNumber *_key;
@property (nonatomic, strong) NSTimer *_timer; // Kosick - 시간 뒤에 꺼지는 기능을 위한 타이머
@end
