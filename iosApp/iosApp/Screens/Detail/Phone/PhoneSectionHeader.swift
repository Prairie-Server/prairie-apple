#if !os(tvOS)
import SwiftUI

/// Editorial section header used below the phone hero. A small tracked
/// all-caps "eyebrow" sits over a larger display title — the same
/// pattern as `TVSectionHeader`, scaled to phones.
struct PhoneSectionHeader: View {
    let label: String
    let title: String
    var trailingText: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundColor(.continuumOnSurface.opacity(0.55))

                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.continuumOnSurface)
            }

            Spacer(minLength: 8)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.continuumSecondaryText)
            }
        }
    }
}
#endif
