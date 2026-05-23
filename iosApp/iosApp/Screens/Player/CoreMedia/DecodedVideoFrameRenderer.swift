import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class DecodedVideoFrameRenderer {
    enum RenderResult {
        case enqueued(count: UInt64, formatChanged: Bool, requiresFlushToResumeDecoding: Bool, rendererFailed: Bool)
        case failed(OSStatus)
    }

    private var lastFormatDescription: CMFormatDescription?
    private(set) var enqueueCount: UInt64 = 0

    func reset() {
        lastFormatDescription = nil
        enqueueCount = 0
    }

    func render(
        imageBuffer: CVImageBuffer,
        layer: AVSampleBufferDisplayLayer
    ) -> RenderResult {
        var imageFormatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &imageFormatDescription
        )
        guard formatStatus == noErr, let imageFormatDescription else {
            return .failed(formatStatus)
        }

        var formatChanged = false
        if let previous = lastFormatDescription {
            if !CMFormatDescriptionEqual(previous, otherFormatDescription: imageFormatDescription) {
                layer.sampleBufferRenderer.flush()
                lastFormatDescription = imageFormatDescription
                formatChanged = true
            }
        } else {
            lastFormatDescription = imageFormatDescription
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = withUnsafePointer(to: &timing) { timingPointer in
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescription: imageFormatDescription,
                sampleTiming: timingPointer,
                sampleBufferOut: &sampleBuffer
            )
        }
        guard sampleStatus == noErr, let sampleBuffer else {
            return .failed(sampleStatus)
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ) as? [CFMutableDictionary], let first = attachments.first {
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        let renderer = layer.sampleBufferRenderer
        renderer.enqueue(sampleBuffer)
        enqueueCount &+= 1

        let requiresFlush = renderer.requiresFlushToResumeDecoding
        if requiresFlush {
            renderer.flush()
        }

        return .enqueued(
            count: enqueueCount,
            formatChanged: formatChanged,
            requiresFlushToResumeDecoding: requiresFlush,
            rendererFailed: renderer.status == .failed
        )
    }
}
