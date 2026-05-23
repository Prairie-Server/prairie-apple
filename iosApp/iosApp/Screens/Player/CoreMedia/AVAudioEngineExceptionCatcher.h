//
//  AVAudioEngineExceptionCatcher.h
//  Continuum
//

#ifndef AVAudioEngineExceptionCatcher_h
#define AVAudioEngineExceptionCatcher_h

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

@interface AVAudioEngineExceptionCatcher : NSObject

+ (BOOL)configure:(AVAudioEngine * _Nonnull)engine
       sourceNode:(AVAudioSourceNode * _Nonnull)sourceNode
        timePitch:(AVAudioUnitTimePitch * _Nonnull)timePitch
           format:(AVAudioFormat * _Nonnull)format
 errorDescription:(NSString * _Nullable * _Nullable)errorDescription;

@end

#endif /* AVAudioEngineExceptionCatcher_h */
