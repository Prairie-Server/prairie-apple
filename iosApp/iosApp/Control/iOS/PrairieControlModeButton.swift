#if os(iOS)
import SwiftUI

struct PrairieControlModeButton: View {
    @Bindable var controller: PrairieControlClient
    let onChooseTarget: () -> Void

    var body: some View {
        if controller.remotePlaybackEngaged {
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
            .accessibilityValue("Active")
        } else {
            Button(action: onChooseTarget) {
                buttonLabel(isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remote Control")
        }
    }

    private func buttonLabel(isActive: Bool) -> some View {
        Image(systemName: isActive ? "appletvremote.gen4.fill" : "appletvremote.gen4")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isActive ? Color.prairieAccent : Color.prairieOnSurface)
            .frame(width: PrairieTheme.topBarIconHitSize, height: PrairieTheme.topBarIconHitSize)
            .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 20) {
        PrairieControlModeButton(controller: PrairieControlClient(), onChooseTarget: {})
    }
    .padding()
    .background(Color.prairieBackground)
}
#endif
#endif
