#if os(tvOS)
import SwiftUI

/// Editorial section header used below the detail hero. A small tracked
/// all-caps "eyebrow" label sits above a larger display title — a pattern
/// Infuse / VidHub lean on to separate the hero from the scroll body
/// without shouting. Single-line, tight stack, no underline or chrome.
struct TVSectionHeader: View {
    let label: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 20, weight: .bold))
                .tracking(3.0)
                .foregroundColor(.continuumOnSurface.opacity(0.55))

            Text(title)
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
        }
    }
}
#endif
