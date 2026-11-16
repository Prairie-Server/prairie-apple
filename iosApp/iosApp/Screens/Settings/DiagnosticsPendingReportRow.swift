#if os(iOS)
import SwiftUI

struct DiagnosticsPendingReportRow: View {
    let report: PendingReport
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.binding.type.listTitle)
                .foregroundStyle(Color.prairieOnSurface)

            Text(report.binding.capturedAtDate, format: .dateTime.month().day().hour().minute())
                .font(.footnote)
                .foregroundStyle(Color.prairieSecondaryText)

            Text(.diagnosticsReportExpiresRelative(
                expiryDate.formatted(.relative(presentation: .named).locale(locale))
            ))
                .font(.footnote)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var expiryDate: Date {
        report.binding.capturedAtDate.addingTimeInterval(PendingReportStore.expiryInterval)
    }
}
#endif
