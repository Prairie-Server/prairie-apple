#if os(tvOS)
import SwiftUI

// MARK: - Primary pill

/// VidHub-style primary play button. Solid white, large, dominant —
/// this is the one element the eye should land on first in the hero.
struct TVPrimaryPillButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var prefersDefaultFocus: Bool = false
    var defaultFocusNamespace: Namespace.ID? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .bold))
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(TVPillButtonStyle(kind: .primary))
        .applyDefaultFocusIfNeeded(prefersDefaultFocus, namespace: defaultFocusNamespace)
    }
}

private extension View {
    @ViewBuilder
    func applyDefaultFocusIfNeeded(_ prefersDefaultFocus: Bool, namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.prefersDefaultFocus(prefersDefaultFocus, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Secondary pill

/// Apple-TV-style dark secondary pill. Sits next to `TVPrimaryPillButton`
/// in the hero row. Filled dark capsule with white icon + label — Apple
/// uses this for "Play Free Episode" alongside a white "Subscribe"
/// button; we use it for "Start Over" alongside a white "Resume …".
struct TVSecondaryPillButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(TVPillButtonStyle(kind: .secondary))
    }
}

// MARK: - Version picker

/// Version-picker pill used in the hero action row. A single consolidated
/// control — stack icon + the effective version's compact quality label
/// (e.g. "4K · HDR") — that opens a `Menu` picker. Mirrors the Infuse /
/// VidHub pattern where one button handles all version selection and
/// audio/subtitle picking is deferred to the player.
struct TVVersionPillButton<MenuContent: View>: View {
    let currentLabel: String
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 24, weight: .semibold))
                Text(currentLabel)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .opacity(0.7)
            }
            .frame(minWidth: 190)
        }
        .menuStyle(.button)
        .buttonStyle(TVPillButtonStyle(kind: .secondary))
    }
}

/// Non-interactive placeholder that reserves the version picker footprint
/// while the next-up episode's playback metadata is loading.
struct TVVersionPillPlaceholder: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 24, weight: .semibold))
            Text("Version")
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .bold))
                .opacity(0.35)
        }
        .foregroundColor(.white.opacity(0.58))
        .frame(minWidth: 190)
        .padding(.horizontal, 40)
        .padding(.vertical, 22)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(
            Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1.2)
        )
        .redacted(reason: .placeholder)
        .focusable(false)
    }
}

// MARK: - Circle menu button

/// Circle-shaped overflow/"more" button that opens a `Menu`. Same visual
/// footprint as `TVCircleActionButton` — used in the hero action row to
/// keep secondary navigation actions (Go to Series, Go to Season, etc.)
/// one tap away without crowding the primary row.
struct TVCircleMenuButton<MenuContent: View>: View {
    let icon: String
    let accessibilityLabel: String
    @ViewBuilder let menu: () -> MenuContent

    init(
        icon: String = "ellipsis",
        accessibilityLabel: String,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.menu = menu
    }

    var body: some View {
        Menu {
            menu()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .menuStyle(.button)
        .buttonStyle(TVCircleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Circle button

/// Compact icon-only secondary action circle. Infuse keeps these small
/// and quiet so the primary play button dominates; we do the same. Used
/// for Favorite / Watchlist / Info in the hero row.
struct TVCircleActionButton: View {
    let icon: String
    let iconActive: String?
    let isActive: Bool
    let accessibilityLabel: String
    let action: () -> Void

    init(
        icon: String,
        iconActive: String? = nil,
        isActive: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconActive = iconActive
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    private var resolvedIcon: String {
        if isActive, let iconActive { return iconActive }
        return icon
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 28, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(TVCircleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Pill ButtonStyle

/// Shared ButtonStyle for the hero's pill controls. Owns all focus
/// appearance via `@Environment(\.isFocused)` — critical on tvOS, where
/// using `.buttonStyle(.plain)` with an external `@FocusState` still
/// lets the system paint its default white focus halo around the
/// button's bounds. A custom `ButtonStyle` fully suppresses that.
struct TVPillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        TVPillButtonBody(configuration: configuration, kind: kind)
    }
}

private struct TVPillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TVPillButtonStyle.Kind

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(foreground)
            .padding(.horizontal, kind == .primary ? 54 : 40)
            .padding(.vertical, kind == .primary ? 26 : 22)
            .overlay(
                Capsule().stroke(
                    innerBorderColor,
                    lineWidth: innerBorderWidth
                )
            )
            .background(Capsule().fill(background))
            .overlay {
                if isFocused {
                    Capsule()
                        .stroke(focusOutlineColor, lineWidth: focusOutlineWidth)
                        .padding(-focusOutlineInset)
                }
            }
            .scaleEffect(scale)
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
            .shadow(
                color: Color.continuumOnSurface.opacity(focusGlowOpacity),
                radius: focusGlowRadius,
                y: 0
            )
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .black
        case .secondary: return isFocused ? .black : .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary:
            return isFocused ? .white : Color.white.opacity(0.76)
        case .secondary:
            return isFocused ? .white : Color.black.opacity(0.52)
        }
    }

    private var innerBorderColor: Color {
        if isFocused {
            return Color.black.opacity(kind == .primary ? 0.18 : 0.12)
        }
        switch kind {
        case .primary:
            return Color.white.opacity(0.12)
        case .secondary:
            return Color.white.opacity(0.24)
        }
    }

    private var innerBorderWidth: CGFloat {
        if isFocused {
            return kind == .primary ? 1.8 : 1.5
        }
        return kind == .primary ? 0.8 : 1.2
    }

    private var focusOutlineColor: Color {
        kind == .primary ? Color.white.opacity(0.94) : Color.white.opacity(0.98)
    }

    private var focusOutlineWidth: CGFloat {
        kind == .primary ? 4 : 3.5
    }

    private var focusOutlineInset: CGFloat {
        kind == .primary ? 7 : 6
    }

    private var scale: CGFloat {
        let base: CGFloat = isFocused
            ? (kind == .primary ? 1.085 : 1.06)
            : 1.0
        return configuration.isPressed ? base * 0.98 : base
    }

    private var shadowOpacity: Double {
        switch kind {
        case .primary: return isFocused ? 0.42 : 0.20
        case .secondary: return isFocused ? 0.36 : 0.18
        }
    }

    private var shadowRadius: CGFloat {
        switch kind {
        case .primary: return isFocused ? 24 : 6
        case .secondary: return isFocused ? 20 : 4
        }
    }

    private var shadowY: CGFloat { isFocused ? 10 : 2 }

    private var focusGlowOpacity: Double {
        isFocused ? 0.18 : 0
    }

    private var focusGlowRadius: CGFloat {
        isFocused ? (kind == .primary ? 14 : 12) : 0
    }
}

// MARK: - Circle ButtonStyle

struct TVCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVCircleButtonBody(configuration: configuration)
    }
}

private struct TVCircleButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(isFocused ? .black : .white)
            .frame(width: 72, height: 72)
            .background(
                Circle().fill(
                    isFocused ? .white : Color.white.opacity(0.10)
                )
            )
            .overlay(
                Circle().stroke(
                    isFocused ? Color.black.opacity(0.12) : Color.white.opacity(0.34),
                    lineWidth: isFocused ? 1.6 : 1.4
                )
            )
            .overlay {
                if isFocused {
                    Circle()
                        .stroke(Color.white.opacity(0.96), lineWidth: 3)
                        .padding(-5)
                }
            }
            .scaleEffect(scale)
            .shadow(
                color: .black.opacity(isFocused ? 0.34 : 0.0),
                radius: isFocused ? 16 : 0,
                y: isFocused ? 6 : 0
            )
            .shadow(
                color: Color.continuumOnSurface.opacity(isFocused ? 0.15 : 0),
                radius: isFocused ? 10 : 0,
                y: 0
            )
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }

    private var scale: CGFloat {
        let base: CGFloat = isFocused ? 1.1 : 1.0
        return configuration.isPressed ? base * 0.95 : base
    }
}
#endif
