//
//  AVDisplayCriteriaPrivate.h
//  Continuum
//
//  Exposes the tvOS-private `AVDisplayCriteria` initializer that accepts a
//  refresh rate and video dynamic range. Apple's public SDK ships
//  `AVDisplayCriteria` as an opaque type with no constructor, but the
//  runtime class does expose `-initWithRefreshRate:videoDynamicRange:` on
//  tvOS, which is what we need to drive HDMI-mode negotiation before
//  starting playback.
//
//  Usage risk: this is a private API. It has historically been accepted by
//  App Review, but could be rejected or removed in a future tvOS release.
//  Callers must availability-guard the cast and fall back to SDR / default
//  refresh when the initializer is not available at runtime.
//

#ifndef AVDisplayCriteriaPrivate_h
#define AVDisplayCriteriaPrivate_h

#if __has_include(<AVFoundation/AVDisplayCriteria.h>)
#import <AVFoundation/AVDisplayCriteria.h>
#import "AVAudioEngineExceptionCatcher.h"

@interface AVDisplayCriteria ()
@property (readonly, nonatomic) float refreshRate;
@property (readonly) int videoDynamicRange;
- (instancetype)initWithRefreshRate:(float)refreshRate
                   videoDynamicRange:(int)videoDynamicRange;
@end

#endif
#endif /* AVDisplayCriteriaPrivate_h */
