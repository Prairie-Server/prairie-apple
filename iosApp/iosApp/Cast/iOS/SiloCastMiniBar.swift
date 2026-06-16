#if os(iOS)
import SwiftUI

/// Persistent "Playing on <TV>" bar shown above the tab content whenever a cast
/// session is active and the full remote is dismissed. Tapping reopens the remote.
struct SiloCastMiniBar: View {
    @Bindable var controller: SiloCastController
    @State private var artwork = SiloCastArtworkResolver()

    var body: some View {
        if controller.hasActiveSession && !controller.isShowingRemoteControl {
            Button { controller.showRemoteControl() } label: {
                HStack(spacing: 12) {
                    thumb
                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.state?.title ?? "Connected")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("Playing on \(controller.activeTarget?.name ?? "Silo TV")")
                            .font(.caption)
                            .foregroundStyle(Color.continuumSecondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        controller.togglePlayPauseOptimistic()
                    } label: {
                        Image(systemName: controller.clock.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(controller.clock.isPlaying ? "Pause" : "Play")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.continuumOutline, lineWidth: 1))
                .foregroundStyle(Color.continuumOnSurface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: controller.state?.contentId) {
                await artwork.resolve(contentId: controller.state?.contentId)
            }
        }
    }

    @ViewBuilder
    private var thumb: some View {
        if let url = artwork.posterURL, !url.isEmpty {
            AsyncImageView(url: url, contentMode: .fill)
                .frame(width: 34, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.continuumSurfaceElevated)
                .frame(width: 34, height: 50)
                .overlay { Image(systemName: "tv").foregroundStyle(Color.continuumSecondaryText) }
        }
    }
}
#endif
