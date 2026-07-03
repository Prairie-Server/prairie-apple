//
//  VideoDisplayRect.swift
//  Silo (iOS + tvOS + macOS)
//
//  Computes the rect the video occupies inside a host view's bounds for a
//  given gravity — the AVSampleBufferDisplayLayer equivalent of
//  `AVPlayerLayer.videoRect`. The CoreMedia player surfaces use it to size
//  the libass subtitle overlay to the displayed video, so subtitle font
//  scale tracks the video frame rather than the full view (which would make
//  text tiny in landscape and huge in portrait).

import AVFoundation
import CoreGraphics

enum VideoDisplayRect {
    /// - Parameters:
    ///   - videoSize: pixel-aspect-corrected presentation size of the video;
    ///     pass `.zero` when unknown to fall back to `bounds`.
    ///   - bounds: the host view's bounds.
    ///   - gravity: the display layer's video gravity.
    static func compute(
        videoSize: CGSize,
        bounds: CGRect,
        gravity: AVLayerVideoGravity
    ) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, !bounds.isEmpty else {
            return bounds
        }
        switch gravity {
        case .resizeAspect:
            return AVMakeRect(aspectRatio: videoSize, insideRect: bounds)
        default:
            // .resizeAspectFill and .resize cover the whole view; the
            // visible video region is the full bounds.
            return bounds
        }
    }
}
