#if os(iOS)
import SwiftUI

struct PrairieControlModeButton: View {
    @Bindable var controller: PrairieControlClient
    let onChooseTarget: () -> Void

    var body: some View {
        if controller.hasActiveSession {
            Menu {
                Button { controller.showRemoteControl() } label: {
                    Label("Remote Control", systemImage: "slider.horizontal.3")
                }
                Button { onChooseTarget() } label: {
                    Label("Choose TV", systemImage: "tv")
                }
                Divider()
                Button(role: .destructive) { controller.turnOffControlMode() } label: {
                    Label("Turn Off Control Mode", systemImage: "tv.slash")
                }
            } label: {
                buttonLabel(isActive: true)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("TV control mode")
        } else {
            Button(action: onChooseTarget) {
                buttonLabel(isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remote Control")
        }
    }

    private func buttonLabel(isActive: Bool) -> some View {
        Image(systemName: "appletvremote.gen4")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isActive ? Color.continuumBackground : Color.continuumOnSurface)
            .frame(width: ContinuumTheme.topBarIconHitSize, height: ContinuumTheme.topBarIconHitSize)
            .background {
                // Chrome-free at rest (Plex-style); a filled disc appears only
                // while actively controlling a TV so the state stays obvious.
                if isActive {
                    Circle()
                        .fill(Color.continuumOnSurface)
                        .frame(width: 36, height: 36)
                }
            }
            .contentShape(Circle())
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 20) {
        PrairieControlModeButton(controller: PrairieControlClient(), onChooseTarget: {})
    }
    .padding()
    .background(Color.continuumBackground)
}
#endif
#endif
