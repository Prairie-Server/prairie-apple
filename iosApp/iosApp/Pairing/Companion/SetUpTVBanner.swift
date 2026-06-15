#if os(iOS)
import SwiftUI

/// App-wide overlay: when a blank Apple TV is discovered on the LAN, slide in
/// a "Set up Apple TV" banner. Tapping it opens `TVPairingView`. This is the
/// hands-off detection surface.
struct SetUpTVBannerModifier: ViewModifier {
    @State private var browser = TVPairingBrowser()
    @State private var activeTV: DiscoveredTV?
    @State private var dismissed: Set<String> = []

    func body(content: Content) -> some View {
        content
            .task { browser.start() }
            .safeAreaInset(edge: .top) {
                if let tv = candidate {
                    banner(tv)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: candidate)
            .sheet(item: $activeTV) { tv in
                TVPairingView(tv: tv) { activeTV = nil }
            }
    }

    private var candidate: DiscoveredTV? {
        browser.found.first { $0.state == .setup && !dismissed.contains($0.id) }
    }

    @ViewBuilder private func banner(_ tv: DiscoveredTV) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "appletv.fill")
            VStack(alignment: .leading) {
                Text("Set up \(tv.name)?").font(.continuumSubheadline)
                Text("Sign this Apple TV in from your iPhone").font(.continuumCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Up") { activeTV = tv }.buttonStyle(.borderedProminent).controlSize(.small)
            Button { dismissed.insert(tv.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

extension View {
    func setUpTVBanner() -> some View { modifier(SetUpTVBannerModifier()) }
}
#endif
