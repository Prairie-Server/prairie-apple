import CoreMedia
import Foundation
import Libavcodec
import VideoToolbox

final class CompressedVideoPipeline {
    struct SubmitOutcome {
        let submission: VideoToolboxVideoDecoder.SubmissionResult
        let pts: CMTime
        let rawPacketSize: Int
        let decoderResetApplied: Bool
    }

    private var hasLoggedCompressedSampleTimingMode = false
    private var hasLoggedCompressedVideoPacketFormat = false
    private var compressedVideoPacketDiagnosticCount = 0
    private var decoderResetWaitDiagnosticCount = 0

    func resetDiagnostics() {
        hasLoggedCompressedSampleTimingMode = false
        hasLoggedCompressedVideoPacketFormat = false
        compressedVideoPacketDiagnosticCount = 0
        decoderResetWaitDiagnosticCount = 0
    }

    func submitPacket(
        packet: UnsafeMutablePointer<AVPacket>,
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        formatDescription: CMVideoFormatDescription,
        timeBase: AVRational,
        useUntimedSamples: Bool,
        preferredLengthSize: Int,
        isH264: Bool,
        resetDecoderBeforeDecoding: Bool,
        requiresRandomAccessForDecoderReset: Bool,
        decoder: VideoToolboxVideoDecoder,
        isCancelled: @escaping () -> Bool,
        outputHandler: @escaping (OSStatus, VTDecodeInfoFlags, CVImageBuffer?, CMTime, Int) -> Void
    ) -> SubmitOutcome? {
        guard size > 0 else { return nil }
        let pts = packetPTS(packet, timeBase: timeBase)
        let timing = sampleTiming(packet, pts: pts, timeBase: timeBase)
        let compressedSampleTiming: CMSampleTimingInfo? = useUntimedSamples ? nil : timing
        if !hasLoggedCompressedSampleTimingMode {
            hasLoggedCompressedSampleTimingMode = true
            print("[CMP] compressedSampleTiming \(useUntimedSamples ? "none" : "container")")
        }

        let packetFormat = compressedVideoPacketFormat(
            data: data,
            size: size,
            preferredLengthSize: preferredLengthSize,
            isH264: isH264
        )
        let h264Info = isH264
            ? CompressedVideoPacketDiagnostics.h264PacketInfo(
                data: data,
                size: size,
                packetFormat: packetFormat
            )
            : nil
        if isH264 {
            logH264PacketDiagnosticsIfNeeded(
                packet: packet,
                pts: pts,
                data: data,
                size: size,
                preferredLengthSize: preferredLengthSize
            )
        }
        if shouldSkipH264PacketBeforeVideoToolbox(
            info: h264Info,
            packetFormat: packetFormat,
            pts: pts,
            isH264: isH264
        ) {
            return nil
        }

        if resetDecoderBeforeDecoding,
           requiresRandomAccessForDecoderReset,
           !isRandomAccessPacket(packet: packet, isH264: isH264, h264Info: h264Info) {
            logDeferredDecoderResetIfNeeded(
                packet: packet,
                pts: pts,
                isH264: isH264,
                h264Info: h264Info
            )
            return nil
        }

        let sampleBuffer = CompressedVideoSampleBuilder.makeSampleBuffer(
            data: data,
            size: size,
            formatDescription: formatDescription,
            timing: compressedSampleTiming,
            packetFormat: packetFormat
        )
        guard let sampleBuffer else { return nil }

        if resetDecoderBeforeDecoding {
            CMSetAttachment(
                sampleBuffer,
                key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
                value: kCFBooleanTrue,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            )
            print("[CMP] VT decoder reset tag applied pts=\(pts.seconds)")
        }

        let rawPacketSize = Int(packet.pointee.size)
        let submission = decoder.submit(
            sampleBuffer: sampleBuffer,
            isCancelled: isCancelled,
            outputHandler: { status, infoFlags, imageBuffer in
                outputHandler(status, infoFlags, imageBuffer, pts, rawPacketSize)
            }
        )
        return SubmitOutcome(
            submission: submission,
            pts: pts,
            rawPacketSize: rawPacketSize,
            decoderResetApplied: resetDecoderBeforeDecoding
        )
    }

    private func packetPTS(
        _ packet: UnsafeMutablePointer<AVPacket>,
        timeBase: AVRational
    ) -> CMTime {
        let noPts = Int64.min
        let ptsRaw: Int64 = packet.pointee.pts != noPts
            ? packet.pointee.pts
            : (packet.pointee.dts != noPts ? packet.pointee.dts : 0)
        let ptsSeconds = Double(ptsRaw) * Double(timeBase.num) / Double(timeBase.den)
        return CMTime(seconds: ptsSeconds, preferredTimescale: 600)
    }

    private func sampleTiming(
        _ packet: UnsafeMutablePointer<AVPacket>,
        pts: CMTime,
        timeBase: AVRational
    ) -> CMSampleTimingInfo {
        let noPts = Int64.min
        let dts = packet.pointee.dts != noPts
            ? CMTime(
                seconds: Double(packet.pointee.dts) * Double(timeBase.num) / Double(timeBase.den),
                preferredTimescale: 600
            )
            : .invalid
        let duration: CMTime = packet.pointee.duration > 0
            ? CMTime(
                seconds: Double(packet.pointee.duration) * Double(timeBase.num) / Double(timeBase.den),
                preferredTimescale: 600
            )
            : .invalid
        return CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )
    }

    private func logH264PacketDiagnosticsIfNeeded(
        packet: UnsafeMutablePointer<AVPacket>,
        pts: CMTime,
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        preferredLengthSize: Int
    ) {
        guard compressedVideoPacketDiagnosticCount < 3 else { return }
        compressedVideoPacketDiagnosticCount += 1
        let summary = CompressedVideoPacketDiagnostics.h264Summary(
            data: data,
            size: size,
            preferredLengthSize: preferredLengthSize
        )
        print(
            "[CMP-H264-PACKET] index=\(compressedVideoPacketDiagnosticCount) "
            + "pts=\(formatSeconds(pts.seconds))s key=\(Self.isKeyPacket(packet) ? 1 : 0) "
            + "\(summary)"
        )
    }

    private func compressedVideoPacketFormat(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        preferredLengthSize: Int,
        isH264: Bool
    ) -> CompressedVideoPacketFormat {
        let packetFormat: CompressedVideoPacketFormat = {
            if isH264 {
                let preferred = CompressedVideoPacketDiagnostics.h264PacketInfo(
                    data: data,
                    size: size,
                    lengthSize: preferredLengthSize
                )
                if preferred.valid {
                    return .lengthPrefixed(lengthSize: preferredLengthSize)
                }
            }
            if CompressedVideoSampleBuilder.looksLikeAnnexB(data: data, size: size) {
                return .annexB
            }
            return .lengthPrefixed(lengthSize: preferredLengthSize)
        }()
        if !hasLoggedCompressedVideoPacketFormat {
            hasLoggedCompressedVideoPacketFormat = true
            print("[CMP] compressedVideoPacketFormat \(packetFormat.label)")
        }
        return packetFormat
    }

    private func shouldSkipH264PacketBeforeVideoToolbox(
        info: CompressedVideoPacketDiagnostics.H264PacketInfo?,
        packetFormat: CompressedVideoPacketFormat,
        pts: CMTime,
        isH264: Bool
    ) -> Bool {
        guard isH264 else { return false }
        guard let info else { return false }
        guard info.isNonVCLOnly else { return false }
        print(
            "[CMP-H264-PACKET] action=skip_non_vcl format=\(packetFormat.label) "
            + "pts=\(formatSeconds(pts.seconds))s nals=\(info.nalCount) types=\(info.typeList) "
            + "sps=\(info.hasSPS ? 1 : 0) pps=\(info.hasPPS ? 1 : 0)"
        )
        return true
    }

    private func isRandomAccessPacket(
        packet: UnsafeMutablePointer<AVPacket>,
        isH264: Bool,
        h264Info: CompressedVideoPacketDiagnostics.H264PacketInfo?
    ) -> Bool {
        let packetIsKey = Self.isKeyPacket(packet)
        guard isH264 else { return packetIsKey }
        guard let h264Info, h264Info.valid else { return packetIsKey }
        return h264Info.hasIDR || (packetIsKey && h264Info.hasVCL)
    }

    private func logDeferredDecoderResetIfNeeded(
        packet: UnsafeMutablePointer<AVPacket>,
        pts: CMTime,
        isH264: Bool,
        h264Info: CompressedVideoPacketDiagnostics.H264PacketInfo?
    ) {
        guard decoderResetWaitDiagnosticCount < 8 else { return }
        decoderResetWaitDiagnosticCount += 1
        let typeText = isH264 ? (h264Info?.typeList ?? "unknown") : "n/a"
        let idrText = isH264 ? "\((h264Info?.hasIDR ?? false) ? 1 : 0)" : "n/a"
        print(
            "[CMP] VT decoder reset deferred pts=\(formatSeconds(pts.seconds))s "
            + "key=\(Self.isKeyPacket(packet) ? 1 : 0) h264=\(isH264 ? 1 : 0) "
            + "idr=\(idrText) types=\(typeText)"
        )
    }

    private static func isKeyPacket(_ packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        (packet.pointee.flags & 0x1) != 0
    }

    private func formatSeconds(_ seconds: Double) -> String {
        seconds.isFinite ? String(format: "%.3f", seconds) : "nan"
    }
}
