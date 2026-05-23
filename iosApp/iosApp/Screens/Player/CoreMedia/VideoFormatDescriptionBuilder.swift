import CoreMedia
import CoreVideo
import Foundation
import Libavcodec

struct VideoFormatDescriptionBuilder {
    struct BuildResult {
        let status: OSStatus
        let formatDescription: CMVideoFormatDescription?
        let usedH264ParameterSets: Bool
    }

    static func fourCCString(_ value: FourCharCode) -> String {
        String(
            bytes: [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF),
            ],
            encoding: .ascii
        ) ?? "????"
    }

    static func makeCompressedFormatDescription(
        codecpar: AVCodecParameters,
        codecType: CMVideoCodecType,
        extensions: NSDictionary,
        atomsData: Data?
    ) -> BuildResult {
        if codecpar.codec_id == AV_CODEC_ID_H264,
           let atomsData,
           let h264FormatDescription = makeH264FormatDescription(fromAVCC: atomsData) {
            return BuildResult(
                status: noErr,
                formatDescription: h264FormatDescription,
                usedH264ParameterSets: true
            )
        }

        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codecType,
            width: codecpar.width,
            height: codecpar.height,
            extensions: extensions,
            formatDescriptionOut: &formatDescription
        )
        return BuildResult(
            status: status,
            formatDescription: formatDescription,
            usedH264ParameterSets: false
        )
    }

    static func makeRelaxedFormatDescription(
        from formatDescription: CMVideoFormatDescription
    ) -> CMVideoFormatDescription? {
        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let mediaSubtype = CMFormatDescriptionGetMediaSubType(formatDescription)
        let extensionsRef = CMFormatDescriptionGetExtensions(formatDescription)
        let extensions = NSMutableDictionary(dictionary: extensionsRef as NSDictionary? ?? NSDictionary())
        extensions.removeObject(forKey: kCVPixelBufferPixelFormatTypeKey)
        extensions.removeObject(forKey: "EnableHardwareAcceleratedVideoDecoder" as NSString)
        extensions.removeObject(forKey: "RequireHardwareAcceleratedVideoDecoder" as NSString)

        var relaxed: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: mediaSubtype,
            width: dims.width,
            height: dims.height,
            extensions: extensions,
            formatDescriptionOut: &relaxed
        )
        guard status == noErr, let relaxed else {
            print("[CMP] relaxed video format create failed status=\(status)")
            return nil
        }
        print("[CMP] relaxed video format create OK")
        return relaxed
    }

    private static func makeH264FormatDescription(fromAVCC avcC: Data) -> CMVideoFormatDescription? {
        guard avcC.count >= 7 else { return nil }
        let nalLengthSize = Int32((avcC[4] & 0x03) + 1)
        let spsCount = Int(avcC[5] & 0x1F)
        guard spsCount > 0 else { return nil }

        var ranges: [Range<Int>] = []
        var cursor = 6
        for _ in 0..<spsCount {
            guard cursor + 2 <= avcC.count else { return nil }
            let size = (Int(avcC[cursor]) << 8) | Int(avcC[cursor + 1])
            cursor += 2
            guard size > 0, cursor + size <= avcC.count else { return nil }
            ranges.append(cursor..<(cursor + size))
            cursor += size
        }

        guard cursor < avcC.count else { return nil }
        let ppsCount = Int(avcC[cursor])
        cursor += 1
        guard ppsCount > 0 else { return nil }
        for _ in 0..<ppsCount {
            guard cursor + 2 <= avcC.count else { return nil }
            let size = (Int(avcC[cursor]) << 8) | Int(avcC[cursor + 1])
            cursor += 2
            guard size > 0, cursor + size <= avcC.count else { return nil }
            ranges.append(cursor..<(cursor + size))
            cursor += size
        }

        return avcC.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> CMVideoFormatDescription? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            var pointers: [UnsafePointer<UInt8>] = ranges.map { base.advanced(by: $0.lowerBound) }
            var sizes: [Int] = ranges.map(\.count)
            var formatDescription: CMVideoFormatDescription?
            let status = pointers.withUnsafeMutableBufferPointer { ptrs in
                sizes.withUnsafeMutableBufferPointer { sizesBuffer in
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: ranges.count,
                        parameterSetPointers: ptrs.baseAddress!,
                        parameterSetSizes: sizesBuffer.baseAddress!,
                        nalUnitHeaderLength: nalLengthSize,
                        formatDescriptionOut: &formatDescription
                    )
                }
            }
            if status != noErr {
                print("[CMP] CMVideoFormatDescriptionCreateFromH264ParameterSets failed status=\(status)")
                return nil
            }
            return formatDescription
        }
    }
}
