#if os(iOS)
import SwiftUI

struct SiloCastControlModeButton: View {
    @Bindable var controller: SiloCastController
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
            .accessibilityLabel("Cast to TV")
        }
    }

    private func buttonLabel(isActive: Bool) -> some View {
        Image(systemName: "airplayvideo")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isActive ? Color.continuumBackground : Color.continuumOnSurface)
            .frame(width: 40, height: 40)
            .background {
                Circle().fill(isActive ? Color.continuumOnSurface : Color.continuumChromeRestingFill)
            }
            .overlay {
                Circle().stroke(isActive ? Color.clear : Color.continuumOutline, lineWidth: 1)
            }
            .contentShape(Circle())
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 20) {
        SiloCastControlModeButton(controller: SiloCastController(), onChooseTarget: {})
    }
    .padding()
    .background(Color.continuumBackground)
}
#endif
#endif
