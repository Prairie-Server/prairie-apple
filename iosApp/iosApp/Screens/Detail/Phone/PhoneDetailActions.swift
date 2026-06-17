#if !os(tvOS)
import SwiftUI

// MARK: - Primary play

/// Solid-white capsule play button. Phone-sized — comfortable 52pt
/// touch target with the play icon and label sitting inline.
///
/// `fullWidth` lets the button expand to its container — used in the
/// Apple-TV-style centered hero where Play is the dominant CTA.
struct PhonePrimaryPillButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var fullWidth: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.black)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 24 : 24)
            .frame(height: 52)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary pill

/// Outlined dark capsule sitting next to the primary play button.
/// Used for "Start Over" alongside "Resume …".
struct PhoneSecondaryPillButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Circle action button

/// Compact icon-only circle button (favorite, watchlist, watched). Used
/// to the right of the play pills. 44pt circular touch target.
struct PhoneCircleActionButton: View {
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.18 : 0.10))
                        .overlay(
                            Circle().stroke(
                                Color.white.opacity(isActive ? 0.55 : 0.25),
                                lineWidth: 1
                            )
                        )
                )
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Circle menu (overflow)

/// Circle button that opens a Menu — used for episode → series/season
/// jumps so we don't crowd the primary action row.
struct PhoneCircleMenuButton<MenuContent: View>: View {
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Version pill

/// Single consolidated version-picker button rendered under the action
/// row. Tapping presents the version sheet; the label shows the
/// effective version's compact quality string ("4K · HDR" / "1080p").
struct PhoneVersionPillButton: View {
    let icon: String
    let label: String
    let currentValue: String
    let action: () -> Void

    init(
        icon: String = "rectangle.stack.fill",
        label: String = "Version",
        currentValue: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.currentValue = currentValue
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(currentValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
