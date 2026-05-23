//
//  AVAudioEngineExceptionCatcher.m
//  Continuum
//

#import "AVAudioEngineExceptionCatcher.h"

@implementation AVAudioEngineExceptionCatcher

+ (BOOL)configure:(AVAudioEngine * _Nonnull)engine
       sourceNode:(AVAudioSourceNode * _Nonnull)sourceNode
        timePitch:(AVAudioUnitTimePitch * _Nonnull)timePitch
           format:(AVAudioFormat * _Nonnull)format
 errorDescription:(NSString * _Nullable * _Nullable)errorDescription
{
    @try {
        [engine attachNode:sourceNode];
        [engine connect:sourceNode to:timePitch format:format];
        [engine connect:timePitch to:engine.mainMixerNode format:format];
        if (format.channelCount > 2) {
            [engine connect:engine.mainMixerNode to:engine.outputNode format:format];
        }
        [engine prepare];
        return YES;
    } @catch (NSException *exception) {
        if (errorDescription != nil) {
            NSString *name = exception.name ?: @"NSException";
            NSString *reason = exception.reason ?: @"unknown reason";
            *errorDescription = [NSString stringWithFormat:@"%@: %@", name, reason];
        }
        return NO;
    }
}

@end
