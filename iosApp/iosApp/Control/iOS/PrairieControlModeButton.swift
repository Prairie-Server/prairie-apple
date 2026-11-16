#if os(iOS)
import SwiftUI

/// The top bar's Remote button. At rest it is a bare glyph that opens the TV
/// picker; while a TV is engaged it is a filled disc that opens the engaged
/// menu, so the bar shows at a glance that Play goes to the TV.
struct PrairieControlModeButton: View {
    let controller: PrairieControlClient
    let onChooseTarget: () -> Void

    var body: some View {
        if controller.remotePlaybackEngaged {
            Menu {
                PrairieControlEngagedMenuItems(
                    controller: controller,
                    onShowRemote: { controller.showRemoteControl() },
                    onChooseTarget: onChooseTarget
                )
            } label: {
                buttonLabel(isActive: true)
            }
            .menuStyle(.borderlessButton)
            .prairieControlEngagedAccessibility(controller)
        } else {
            Button(action: onChooseTarget) {
                buttonLabel(isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.castPickerRemoteControl))
        }
    }

    private func buttonLabel(isActive: Bool) -> some View {
        Image(systemName: isActive ? "appletvremote.gen4.fill" : "appletvremote.gen4")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isActive ? Color.prairieBackground : Color.prairieOnSurface)
            .frame(width: PrairieTheme.topBarIconHitSize, height: PrairieTheme.topBarIconHitSize)
            .background {
                if isActive {
                    Circle()
                        .fill(Color.prairieOnSurface)
                        .frame(width: Self.activeDiscSize, height: Self.activeDiscSize)
                }
            }
            .contentShape(Rectangle())
    }

    /// Smaller than the 44pt hit area, so the disc sits level with the
    /// profile picture beside it.
    private static let activeDiscSize: CGFloat = 34
}

/// What a Remote button offers while a TV is engaged: the remote, another
/// TV, or turning control mode off. Headed by the TV's name, so the menu
/// says which TV Play goes to.
struct PrairieControlEngagedMenuItems: View {
    let controller: PrairieControlClient
    let onShowRemote: () -> Void
    let onChooseTarget: () -> Void

    var body: some View {
        Section {
            Button(action: onShowRemote) {
                Label(.castPickerRemoteControl, systemImage: "slider.horizontal.3")
            }
            Button(action: onChooseTarget) {
                Label(.remoteChooseTv, systemImage: "tv")
            }
        } header: {
            if let status = controller.engagedStatus {
                Text(status)
            }
        }
        Section {
            Button(role: .destructive) { controller.disconnect() } label: {
                Label(.remoteTurnOffControlMode, systemImage: "tv.slash")
            }
        }
    }
}

extension PrairieControlClient {
    /// "Connected to Living Room", or "Reconnecting to Living Room…" while
    /// the link is down. Nil when no TV is engaged.
    var engagedStatus: LocalizedStringResource? {
        guard remotePlaybackEngaged, let name = engagedTargetName else { return nil }
        return isReconnecting ? .remoteReconnectingTo(name) : .castRemoteConnectedTo(name)
    }
}

extension View {
    /// VoiceOver reads an engaged Remote button as "TV control mode,
    /// Connected to Living Room".
    func prairieControlEngagedAccessibility(_ controller: PrairieControlClient) -> some View {
        accessibilityLabel(Text(.remoteControlMode))
            .accessibilityValue(controller.engagedStatus.map { Text($0) } ?? Text(.remoteControlModeActive))
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
