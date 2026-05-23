import CoreMedia
import Foundation
import Libavformat

enum CompressedVideoPacketFormat: Equatable {
    case lengthPrefixed(lengthSize: Int)
    case annexB

    var label: String {
        switch self {
        case .lengthPrefixed(let lengthSize):
            return "lp\(lengthSize)"
        case .annexB:
            return "annexB"
        }
    }
}

struct CompressedVideoSampleBuilder {
    static func makeSampleBuffer(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        formatDescription: CMVideoFormatDescription,
        timing: CMSampleTimingInfo?,
        packetFormat: CompressedVideoPacketFormat
    ) -> CMSampleBuffer? {
        switch packetFormat {
        case .lengthPrefixed(let lengthSize):
            if lengthSize == 4 {
                return wrap(
                    data: data,
                    size: size,
                    formatDescription: formatDescription,
                    timing: timing
                )
            }
            return convertLengthPrefixedAndWrap(
                data: data,
                size: size,
                sourceLengthSize: lengthSize,
                formatDescription: formatDescription,
                timing: timing
            )
        case .annexB:
            return convertAnnexBAndWrap(
                data: data,
                size: size,
                formatDescription: formatDescription,
                timing: timing
            )
        }
    }

    static func looksLikeAnnexB(data: UnsafeMutablePointer<UInt8>, size: Int) -> Bool {
        guard size >= 3 else { return false }
        if data[0] == 0, data[1] == 0, data[2] == 1 {
            return true
        }
        guard size >= 4 else { return false }
        return data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1
    }

    private static func wrap(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        formatDescription: CMVideoFormatDescription,
        timing: CMSampleTimingInfo?
    ) -> CMSampleBuffer? {
        guard let blockBuffer = makeBlockBuffer(data: data, size: size) else { return nil }
        return makeCompressedSampleBuffer(
            blockBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleSize: size,
            timing: timing
        )
    }

    private static func convertLengthPrefixedAndWrap(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        sourceLengthSize: Int,
        formatDescription: CMVideoFormatDescription,
        timing: CMSampleTimingInfo?
    ) -> CMSampleBuffer? {
        guard sourceLengthSize > 0, sourceLengthSize < 4 else { return nil }
        var ioContext: UnsafeMutablePointer<AVIOContext>?
        guard avio_open_dyn_buf(&ioContext) == 0, let ioContext else { return nil }

        let end = data + size
        var nalStart = data
        while nalStart + sourceLengthSize <= end {
            var nalSize = UInt32(0)
            for i in 0..<sourceLengthSize {
                nalSize = (nalSize << 8) | UInt32(nalStart[i])
            }
            nalStart += sourceLengthSize
            guard nalSize > 0,
                  nalStart.advanced(by: Int(nalSize)) <= end else {
                break
            }
            avio_wb32(ioContext, nalSize)
            avio_write(ioContext, nalStart, Int32(nalSize))
            nalStart += Int(nalSize)
        }

        var convertedBuffer: UnsafeMutablePointer<UInt8>?
        let convertedSize = avio_close_dyn_buf(ioContext, &convertedBuffer)
        guard let convertedBuffer, convertedSize > 0 else { return nil }
        defer { av_free(convertedBuffer) }

        guard let blockBuffer = makeBlockBuffer(data: convertedBuffer, size: Int(convertedSize)) else {
            return nil
        }
        return makeCompressedSampleBuffer(
            blockBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleSize: Int(convertedSize),
            timing: timing
        )
    }

    private static func convertAnnexBAndWrap(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        formatDescription: CMVideoFormatDescription,
        timing: CMSampleTimingInfo?
    ) -> CMSampleBuffer? {
        var ioContext: UnsafeMutablePointer<AVIOContext>?
        guard avio_open_dyn_buf(&ioContext) == 0, let ioContext else { return nil }

        let start = UnsafePointer(data)
        let end = start.advanced(by: size)

        func findStartCode(from ptr: UnsafePointer<UInt8>) -> (nalStart: UnsafePointer<UInt8>, codeSize: Int)? {
            var cursor = ptr
            while cursor < end {
                let remaining = end - cursor
                if remaining >= 4,
                   cursor[0] == 0, cursor[1] == 0, cursor[2] == 0, cursor[3] == 1 {
                    return (cursor.advanced(by: 4), 4)
                }
                if remaining >= 3,
                   cursor[0] == 0, cursor[1] == 0, cursor[2] == 1 {
                    return (cursor.advanced(by: 3), 3)
                }
                cursor = cursor.advanced(by: 1)
            }
            return nil
        }

        guard var current = findStartCode(from: start)?.nalStart else {
            return nil
        }

        while current < end {
            let next = findStartCode(from: current)
            let nalEnd = next?.nalStart.advanced(by: -(next?.codeSize ?? 0)) ?? end
            let nalSize = nalEnd - current
            if nalSize > 0 {
                avio_wb32(ioContext, UInt32(nalSize))
                avio_write(ioContext, current, Int32(nalSize))
            }
            guard let nextStart = next?.nalStart else { break }
            current = nextStart
        }

        var convertedBuffer: UnsafeMutablePointer<UInt8>?
        let convertedSize = avio_close_dyn_buf(ioContext, &convertedBuffer)
        guard let convertedBuffer, convertedSize > 0 else { return nil }
        defer { av_free(convertedBuffer) }

        guard let blockBuffer = makeBlockBuffer(data: convertedBuffer, size: Int(convertedSize)) else {
            return nil
        }
        return makeCompressedSampleBuffer(
            blockBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleSize: Int(convertedSize),
            timing: timing
        )
    }

    private static func makeBlockBuffer(
        data: UnsafeMutablePointer<UInt8>,
        size: Int
    ) -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: size,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: size,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer)
        guard createStatus == noErr, let blockBuffer else { return nil }

        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: data,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: size)
        guard replaceStatus == noErr else { return nil }
        return blockBuffer
    }

    private static func makeCompressedSampleBuffer(
        blockBuffer: CMBlockBuffer,
        formatDescription: CMVideoFormatDescription,
        sampleSize: Int,
        timing: CMSampleTimingInfo?
    ) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        let status: OSStatus
        if var timing {
            var sizes: [Int] = [sampleSize]
            status = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sizes,
                sampleBufferOut: &sampleBuffer)
        } else {
            status = CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 0,
                sampleTimingArray: nil,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer)
        }
        guard status == noErr else { return nil }
        return sampleBuffer
    }

    /// For Profile 4/7 dual-layer HEVC, FFmpeg delivers an elementary stream
    /// that mixes BL VCL NAL units (`nuh_layer_id == 0`) with EL VCL units
    /// (`nuh_layer_id > 0`) and Dolby Vision RPU/metadata NALs
    /// (`nal_unit_type == 62 || 63`, aka UNSPEC62/63). VideoToolbox's HEVC
    /// decoder chokes on these intermittently — the symptom is 5-15 second
    /// decode stalls where vDec=0 and vidEnq=+0 — even though per spec a
    /// single-layer HEVC decoder should just skip them.
    ///
    /// Walk the length-prefixed NAL stream and emit only the BL NALs. The
    /// output keeps the same length-prefix size as the input so the caller
    /// (`wrap` or `convertAndWrap`) handles it identically.
    ///
    /// - Parameter lengthSize: 3 or 4, matching the in-stream length prefix.
    /// - Parameter counter: cumulative-drop counter, incremented per dropped NAL.
    /// - Returns: `(ptr, size, free)` — if anything was dropped, `ptr` points at a
    ///   freshly-allocated buffer and `free == true`; otherwise `ptr == data`.
    static func stripHevcEnhancementLayer(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        lengthSize: Int,
        counter: inout UInt64
    ) -> (ptr: UnsafeMutablePointer<UInt8>, size: Int, free: Bool) {
        precondition(lengthSize == 3 || lengthSize == 4, "HEVC length prefix must be 3 or 4 bytes")
        var cursor = 0
        var keepRanges: [(offset: Int, length: Int)] = []
        var droppedCount: UInt64 = 0

        while cursor + lengthSize + 2 <= size {
            var nalSize: Int = 0
            for i in 0..<lengthSize {
                nalSize = (nalSize << 8) | Int(data[cursor + i])
            }
            let headerOffset = cursor + lengthSize
            guard nalSize >= 2, headerOffset + nalSize <= size else { break }
            let byte0 = data[headerOffset]
            let nalUnitType = (byte0 >> 1) & 0x3F
            // UNSPEC62 / UNSPEC63 are Dolby Vision RPU + metadata NAL units.
            // They're invisible to a spec-compliant HEVC decoder, but VT's
            // HW decoder appears to slow down when it has to skip them per
            // frame. Strip them for the stripped-HDR10 path.
            //
            // DO NOT strip by nuh_layer_id — in practice, stripping EL VCL
            // NALs breaks decode on some Profile 7 rips (VT produces no
            // output), even though per spec a BL-only decoder should just
            // ignore them. Leave VT to skip layer_id > 0 slices itself.
            let isDovi = nalUnitType == 62 || nalUnitType == 63
            if isDovi {
                droppedCount &+= 1
            } else {
                keepRanges.append((cursor, lengthSize + nalSize))
            }
            cursor = headerOffset + nalSize
        }

        counter &+= droppedCount
        guard droppedCount > 0 else {
            return (data, size, false)
        }

        let newSize = keepRanges.reduce(0) { $0 + $1.length }
        guard newSize > 0 else {
            // Every NAL was filtered — give back an empty single-byte buffer
            // and let the caller's size > 0 guard drop the packet.
            return (data, 0, false)
        }
        let newBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: newSize)
        var writeCursor = 0
        for (offset, length) in keepRanges {
            newBuf.advanced(by: writeCursor).initialize(
                from: data.advanced(by: offset), count: length)
            writeCursor += length
        }
        return (newBuf, newSize, true)
    }
}
