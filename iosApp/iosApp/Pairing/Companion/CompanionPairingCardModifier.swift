#if os(iOS)
import SwiftUI

/// App-wide overlay: when a blank Apple TV is discovered on the LAN, present the
/// native-style pairing card (`CompanionPairingCard`) rising from the bottom.
/// Replaces the old top banner. Owns discovery (`TVPairingBrowser`) and
/// per-session "Not Now" dismissal.
struct CompanionPairingCardModifier: ViewModifier {
    @State private var browser = TVPairingBrowser()
    @State private var dismissed: Set<String> = []
    @State private var active: DiscoveredTV?

    func body(content: Content) -> some View {
        content
            .task { browser.start() }
            .onChange(of: candidate) { _, newValue in
                // Latch onto a candidate when nothing is showing. We do NOT
                // auto-clear when it disappears: once setup begins the TV stops
                // advertising, and the card must persist to show progress/result.
                if active == nil, let tv = newValue { active = tv }
            }
            .overlay {
                if let tv = active {
                    CompanionPairingCard(
                        tv: tv,
                        onNotNow: {
                            dismissed.insert(CompanionPairingDismissal.key(id: tv.id, sid: tv.sid))
                            active = nil
                        },
                        onClose: { active = nil }
                    )
                }
            }
    }

    /// First discovered TV awaiting setup whose session hasn't been dismissed.
    private var candidate: DiscoveredTV? {
        browser.found.first {
            $0.state == .setup
                && !dismissed.contains(CompanionPairingDismissal.key(id: $0.id, sid: $0.sid))
        }
    }
}

extension View {
    func companionPairingCard() -> some View { modifier(CompanionPairingCardModifier()) }
}
#endif
