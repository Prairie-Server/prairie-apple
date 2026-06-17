import Foundation

struct DecodeFailureRecoveryPolicy {
    enum Codec {
        case h264
        case hevc
        case other

        var logLabel: String {
            switch self {
            case .h264:
                return "H.264"
            case .hevc:
                return "HEVC"
            case .other:
                return "video"
            }
        }
    }

    static func shouldAttemptBurstResync(
        status: Int32,
        codec: Codec,
        attempts: Int,
        maxAttempts: Int
    ) -> Bool {
        guard attempts < maxAttempts else { return false }

        switch codec {
        case .h264:
            return status == -12909 || status == -8969
        case .hevc:
            return status == -12909
        case .other:
            return false
        }
    }
}
