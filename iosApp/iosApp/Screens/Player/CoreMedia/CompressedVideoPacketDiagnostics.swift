import Foundation

struct CompressedVideoPacketDiagnostics {
    struct H264PacketInfo {
        let valid: Bool
        let nalCount: Int
        let nalTypes: [Int]
        let hasVCL: Bool
        let hasIDR: Bool
        let hasSPS: Bool
        let hasPPS: Bool

        var isNonVCLOnly: Bool {
            valid && nalCount > 0 && !hasVCL
        }

        var typeList: String {
            nalTypes.isEmpty ? "none" : nalTypes.prefix(8).map(String.init).joined(separator: ",")
        }
    }

    static func h264Summary(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        preferredLengthSize: Int?
    ) -> String {
        let bytes = UnsafeBufferPointer(start: data, count: max(0, size))
        let prefix = firstBytesHex(bytes)
        let annexB = annexBNalTypes(bytes)
        let lp4 = lengthPrefixedNalTypes(bytes, lengthSize: 4)
        let lp3 = lengthPrefixedNalTypes(bytes, lengthSize: 3)
        let preferred = preferredLengthSize.map(String.init) ?? "unknown"

        return "size=\(size) firstBytes=\(prefix) preferredLengthSize=\(preferred) "
            + "annexB=\(formatParse(annexB)) "
            + "lp4=\(formatParse(lp4)) "
            + "lp3=\(formatParse(lp3))"
    }

    static func h264PacketInfo(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        packetFormat: CompressedVideoPacketFormat
    ) -> H264PacketInfo {
        let bytes = UnsafeBufferPointer(start: data, count: max(0, size))
        let result: NalParseResult
        switch packetFormat {
        case .annexB:
            result = annexBNalTypes(bytes)
        case .lengthPrefixed(let lengthSize):
            result = lengthPrefixedNalTypes(bytes, lengthSize: lengthSize)
        }
        return H264PacketInfo(
            valid: result.valid,
            nalCount: result.nalCount,
            nalTypes: result.nalTypes,
            hasVCL: result.hasVCL,
            hasIDR: result.hasIDR,
            hasSPS: result.hasSPS,
            hasPPS: result.hasPPS
        )
    }

    static func h264PacketInfo(
        data: UnsafeMutablePointer<UInt8>,
        size: Int,
        lengthSize: Int
    ) -> H264PacketInfo {
        h264PacketInfo(
            data: data,
            size: size,
            packetFormat: .lengthPrefixed(lengthSize: lengthSize)
        )
    }

    private static func firstBytesHex(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
        guard !bytes.isEmpty else { return "empty" }
        return bytes.prefix(16)
            .map { String(format: "%02x", $0) }
            .joined(separator: "")
    }

    private static func formatParse(_ result: NalParseResult) -> String {
        guard result.valid else { return "invalid" }
        let types = result.nalTypes.isEmpty
            ? "none"
            : result.nalTypes.prefix(8).map(String.init).joined(separator: ",")
        return "valid:nals=\(result.nalCount):types=\(types):sps=\(result.hasSPS ? 1 : 0):pps=\(result.hasPPS ? 1 : 0):idr=\(result.hasIDR ? 1 : 0)"
    }

    private struct NalParseResult {
        var valid: Bool
        var nalCount: Int = 0
        var nalTypes: [Int] = []
        var hasVCL: Bool = false
        var hasSPS: Bool = false
        var hasPPS: Bool = false
        var hasIDR: Bool = false
    }

    private static func lengthPrefixedNalTypes(
        _ bytes: UnsafeBufferPointer<UInt8>,
        lengthSize: Int
    ) -> NalParseResult {
        guard lengthSize == 3 || lengthSize == 4, bytes.count > lengthSize else {
            return NalParseResult(valid: false)
        }
        var cursor = 0
        var result = NalParseResult(valid: false)
        while cursor + lengthSize < bytes.count {
            var nalSize = 0
            for i in 0..<lengthSize {
                nalSize = (nalSize << 8) | Int(bytes[cursor + i])
            }
            let nalStart = cursor + lengthSize
            guard nalSize > 0, nalStart + nalSize <= bytes.count else {
                return result.nalCount > 0 ? result : NalParseResult(valid: false)
            }
            result.valid = true
            appendH264NalType(Int(bytes[nalStart] & 0x1F), to: &result)
            cursor = nalStart + nalSize
        }
        return result
    }

    private static func annexBNalTypes(_ bytes: UnsafeBufferPointer<UInt8>) -> NalParseResult {
        guard bytes.count >= 4 else { return NalParseResult(valid: false) }
        var result = NalParseResult(valid: false)
        var current = findStartCode(bytes, from: 0)?.nalStart
        guard current != nil else { return result }

        while let nalStart = current, nalStart < bytes.count {
            let next = findStartCode(bytes, from: nalStart)
            let nalEnd = next?.codeStart ?? bytes.count
            if nalEnd > nalStart {
                result.valid = true
                appendH264NalType(Int(bytes[nalStart] & 0x1F), to: &result)
            }
            current = next?.nalStart
        }
        return result
    }

    private static func findStartCode(
        _ bytes: UnsafeBufferPointer<UInt8>,
        from offset: Int
    ) -> (codeStart: Int, nalStart: Int)? {
        var cursor = max(0, offset)
        while cursor + 3 <= bytes.count {
            if cursor + 4 <= bytes.count,
               bytes[cursor] == 0,
               bytes[cursor + 1] == 0,
               bytes[cursor + 2] == 0,
               bytes[cursor + 3] == 1 {
                return (cursor, cursor + 4)
            }
            if bytes[cursor] == 0,
               bytes[cursor + 1] == 0,
               bytes[cursor + 2] == 1 {
                return (cursor, cursor + 3)
            }
            cursor += 1
        }
        return nil
    }

    private static func appendH264NalType(_ type: Int, to result: inout NalParseResult) {
        result.nalCount += 1
        result.nalTypes.append(type)
        if (1...5).contains(type) { result.hasVCL = true }
        if type == 7 { result.hasSPS = true }
        if type == 8 { result.hasPPS = true }
        if type == 5 { result.hasIDR = true }
    }
}
