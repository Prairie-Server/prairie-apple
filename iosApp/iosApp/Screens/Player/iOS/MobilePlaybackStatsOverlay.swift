#if os(iOS)
import SwiftUI

/// Infuse-style stats annotation: `PlaybackStats.overlayRows` drawn over the
/// picture on a low-contrast dark plate, with no header, close button or
/// scroll affordance.
///
/// Two properties matter and are easy to break:
///
/// - It is inert. `allowsHitTesting(false)` means a tap in its footprint
///   still reaches the transport and the gesture layer underneath — the
///   overlay must never cost the user a play/pause. That rules out
///   scrolling, which is why it leaves out the engine rows the settings
///   sheet's Technical details page and the tvOS pane scroll through.
/// - It outlives the controls. It sits outside the `showControls` gate in
///   `MobilePlayerControls`, so the auto-hide takes the transport away
///   and leaves the stats up. Toggled off from where it was toggled on
///   (settings sheet → Stats), which is why there is no dismiss control.
struct MobilePlaybackStatsOverlay: View {
    let stats: PlaybackStats

    /// Clears the control overlay's top strip so the two never collide.
    private static let topInset: CGFloat = 60

    var body: some View {
        // Side by side when the phone is wide enough (landscape), stacked with
        // a shorter event list otherwise, so the plate never runs off-screen.
        ViewThatFits(in: .horizontal) {
            plate(stacked: false)
            plate(stacked: true)
        }
        .padding(.leading, 16)
        .padding(.top, Self.topInset)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
    }

    private func plate(stacked: Bool) -> some View {
        content(stacked: stacked)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // Flat translucent black rather than a material: a blur reads as
            // a window, which is exactly what this shouldn't look like. Just
            // enough to hold white text over a bright scene.
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.38))
            )
            // Hug the rows so the plate never spans the player.
            .fixedSize()
    }

    @ViewBuilder
    private func content(stacked: Bool) -> some View {
        let panel = PlaybackStatsPanel(stats: stats, layout: .plain)
        let hasEvents = !stats.recentEvents.isEmpty
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                rows(panel)
                if hasEvents {
                    panel.plainEventList(limit: 4)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                rows(panel)
                if hasEvents {
                    panel.plainEventList(limit: PlaybackEventLog.defaultCapacity)
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ panel: PlaybackStatsPanel) -> some View {
        // Gated on the overlay set, not `hasRows`: early snapshots can carry
        // only rows this overlay leaves out, which would draw a blank plate.
        if !stats.overlayRows.isEmpty {
            panel
        } else {
            Text(.playerStatsAppearOnceStarted)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
#endif
