#if os(iOS) || os(tvOS)
import Foundation

struct DiagnosticsPrompt: Identifiable, Equatable {
    let id = UUID()
    let reports: [PendingReport]

    var title: String {
        reports.count == 1 ? "Send a diagnostics report?" : "Send diagnostics reports?"
    }

    var message: String {
        let count = reports.count
        let types = Set(reports.map(\.binding.type))
        let recipient = reports.allSatisfy { $0.binding.binding.destinationChoice == .hosted }
            ? "the Prairie Diagnostics team"
            : "your server administrator"
        if count == 1, let type = reports.first?.binding.type {
            return Self.singleMessage(for: type, recipient: recipient)
        }
        if types.count == 1, let type = types.first {
            switch type {
            case .crash, .nativeCrash:
                return "Prairie crashed \(count) times. You can review the reports before sending them to \(recipient)."
            case .hang, .anr:
                return "Prairie was not responding \(count) times. You can review the reports before sending them to \(recipient)."
            case .abnormalExit:
                return "Prairie did not shut down cleanly \(count) times. You can review the reports before sending them to \(recipient)."
            case .manual:
                return "Prairie has \(count) pending diagnostics reports."
            }
        }

        let descriptions = types.map(Self.shortDescription(for:)).sorted().joined(separator: ", ")
        return "Prairie has \(count) pending reports covering \(descriptions). You can review them before sending."
    }

    private static func singleMessage(for type: ReportType, recipient: String) -> String {
        switch type {
        case .crash, .nativeCrash:
            return "Prairie crashed recently. Sending a diagnostics report can help \(recipient) understand what happened."
        case .hang, .anr:
            return "Prairie was not responding recently. Sending a diagnostics report can help \(recipient) understand what happened."
        case .abnormalExit:
            return "Prairie did not shut down cleanly last time. Sending a diagnostics report can help \(recipient) understand what happened."
        case .manual:
            return "Prairie has a pending diagnostics report."
        }
    }

    private static func shortDescription(for type: ReportType) -> String {
        switch type {
        case .crash, .nativeCrash:
            return "a crash"
        case .hang, .anr:
            return "a period when Prairie was not responding"
        case .abnormalExit:
            return "an unclean shutdown"
        case .manual:
            return "a manual report"
        }
    }
}
#endif
