import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class VideoToolboxVideoDecoder {
    struct CreateResult {
        let status: OSStatus
        let session: VTDecompressionSession?
    }

    enum SubmissionResult {
        case submitted
        case submitFailed(OSStatus)
        case unavailable
        case cancelled
    }

    private(set) var session: VTDecompressionSession?
    private let maxInFlightSubmissions: Int
    private let inFlightCondition = NSCondition()
    private var inFlightSubmissions = 0

    init(maxInFlightSubmissions: Int) {
        self.maxInFlightSubmissions = maxInFlightSubmissions
    }

    var isInstalled: Bool {
        session != nil
    }

    func install(session: VTDecompressionSession) {
        invalidate()
        self.session = session
    }

    static func decoderSpecification(for formatDescription: CMVideoFormatDescription) -> CFDictionary? {
        let extensions = CMFormatDescriptionGetExtensions(formatDescription) as NSDictionary? ?? NSDictionary()
        let spec = NSMutableDictionary(dictionary: extensions)
        spec[kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = kCFBooleanTrue

        #if !targetEnvironment(simulator)
        let subtype = CMFormatDescriptionGetMediaSubType(formatDescription)
        if subtype == kCMVideoCodecType_H264 || subtype == kCMVideoCodecType_HEVC {
            spec[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder] = kCFBooleanTrue
        }
        #endif

        return spec
    }

    func createSession(
        formatDescription: CMVideoFormatDescription,
        decoderSpecification: CFDictionary?,
        imageBufferAttributes: NSDictionary,
        label: String
    ) -> CreateResult {
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification,
            imageBufferAttributes: imageBufferAttributes,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        if status == noErr {
            print("[CMP] VT create \(label) OK")
            if let newSession {
                logHardwareUsage(session: newSession, label: label)
            }
        } else {
            print("[CMP] VT create \(label) failed status=\(status)")
        }
        return CreateResult(status: status, session: newSession)
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        resetBackpressure()
    }

    func waitForAsynchronousFrames() {
        guard let session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    func wakeWaiters() {
        inFlightCondition.lock()
        inFlightCondition.broadcast()
        inFlightCondition.unlock()
    }

    func resetBackpressure() {
        inFlightCondition.lock()
        inFlightSubmissions = 0
        inFlightCondition.broadcast()
        inFlightCondition.unlock()
    }

    func inFlightCount() -> Int {
        inFlightCondition.lock()
        defer { inFlightCondition.unlock() }
        return inFlightSubmissions
    }

    func submit(
        sampleBuffer: CMSampleBuffer,
        isCancelled: () -> Bool,
        outputHandler: @escaping (OSStatus, VTDecodeInfoFlags, CVImageBuffer?) -> Void
    ) -> SubmissionResult {
        guard let session else { return .unavailable }
        guard waitForDecodeSlot(isCancelled: isCancelled) else { return .cancelled }

        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: flags,
            infoFlagsOut: &infoFlags,
            outputHandler: { [weak self] status, infoFlags, imageBuffer, _, _ in
                defer { self?.finishDecodeSubmission() }
                outputHandler(status, infoFlags, imageBuffer)
            }
        )
        if status != noErr {
            finishDecodeSubmission()
            return .submitFailed(status)
        }
        return .submitted
    }

    private func waitForDecodeSlot(isCancelled: () -> Bool) -> Bool {
        inFlightCondition.lock()
        defer { inFlightCondition.unlock() }

        while inFlightSubmissions >= maxInFlightSubmissions,
              !isCancelled() {
            inFlightCondition.wait(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard !isCancelled() else { return false }
        inFlightSubmissions += 1
        return true
    }

    private func finishDecodeSubmission() {
        inFlightCondition.lock()
        if inFlightSubmissions > 0 {
            inFlightSubmissions -= 1
        }
        inFlightCondition.signal()
        inFlightCondition.unlock()
    }

    private func logHardwareUsage(session: VTDecompressionSession, label: String) {
        var value: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            VTSessionCopyProperty(
                session,
                key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                allocator: kCFAllocatorDefault,
                valueOut: UnsafeMutableRawPointer(pointer)
            )
        }
        guard status == noErr, let value else {
            print("[CMP] VT usingHardware unavailable label=\(label) status=\(status)")
            return
        }

        let usingHardware: Bool
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            usingHardware = CFBooleanGetValue((value as! CFBoolean))
        } else if let number = value as? NSNumber {
            usingHardware = number.boolValue
        } else {
            print("[CMP] VT usingHardware unexpected type label=\(label)")
            return
        }

        print("[CMP] VT usingHardware=\(usingHardware ? 1 : 0) label=\(label)")
    }
}
