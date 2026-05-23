import SwiftUI

/// Modal number-pad for entering a 4-digit profile PIN.
struct PINEntryView: View {
    let profile: UserProfile
    let onComplete: (String) -> Void
    let onCancel: (() -> Void)?

    @State private var pin: String = ""
    @State private var isShaking: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let maxDigits = 4

    // 3-column grid for the number pad
    private let padColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    init(
        profile: UserProfile,
        onCancel: (() -> Void)? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        self.profile = profile
        self.onCancel = onCancel
        self.onComplete = onComplete
    }

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        phoneBody
        #endif
    }

    private var phoneBody: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                header(avatarSize: 64)
                .padding(.top, ContinuumTheme.largePadding)

                pinDots(dotSize: 20, spacing: 20)

                Spacer()

                numberPad
                .padding(.horizontal, ContinuumTheme.largePadding)

                cancelButton
                .padding(.bottom, ContinuumTheme.largePadding)
            }
        }
    }

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 28) {
                header(avatarSize: 84)
                pinDots(dotSize: 24, spacing: 24)
                numberPad
                cancelButton
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(width: 620)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.continuumSurfaceElevated.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 36, y: 18)
            .focusSection()
        }
        .onExitCommand(perform: cancel)
    }
    #endif

    private func header(avatarSize: CGFloat) -> some View {
        VStack(spacing: 10) {
            ProfileAvatarView(
                avatar: profile.avatarEmoji,
                name: profile.name,
                size: avatarSize
            )

            Text("Enter PIN for \(profile.name)")
                .font(.continuumSubheadline)
                .foregroundColor(.continuumOnSurface)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func pinDots(dotSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<maxDigits, id: \.self) { index in
                Circle()
                    .fill(index < pin.count ? Color.continuumPrimary : Color.continuumSurfaceVariant)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .offset(x: isShaking ? -8 : 0)
        .animation(
            isShaking
                ? .default.repeatCount(3, autoreverses: true).speed(6)
                : .default,
            value: isShaking
        )
    }

    private var numberPad: some View {
        LazyVGrid(columns: padColumns, spacing: 16) {
            ForEach(1...9, id: \.self) { digit in
                NumberPadButton(label: "\(digit)") {
                    appendDigit("\(digit)")
                }
            }

            Color.clear.frame(height: NumberPadButton.size)

            NumberPadButton(label: "0") {
                appendDigit("0")
            }

            NumberPadButton(label: "delete.backward", isSystemImage: true) {
                deleteDigit()
            }
        }
        #if os(tvOS)
        .frame(width: 360)
        #endif
    }

    private var cancelButton: some View {
        Button("Cancel", action: cancel)
            .buttonStyle(ContinuumTextButtonStyle())
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func appendDigit(_ digit: String) {
        guard pin.count < maxDigits else { return }
        pin += digit

        if pin.count == maxDigits {
            onComplete(pin)
        }
    }

    private func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    /// Trigger a shake animation (e.g., on wrong PIN).
    func shakeAndReset() {
        isShaking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isShaking = false
            pin = ""
        }
    }
}

// MARK: - Number Pad Button

private struct NumberPadButton: View {
    let label: String
    var isSystemImage: Bool = false
    let action: () -> Void
    static var size: CGFloat {
        #if os(tvOS)
        96
        #else
        64
        #endif
    }

    var body: some View {
        Button(action: action) {
            if isSystemImage {
                Image(systemName: label)
                    .font(.system(size: symbolSize, weight: .semibold))
            } else {
                Text(label)
                    .font(.continuumPIN)
            }
        }
        .buttonStyle(NumberPadButtonStyle())
    }

    private var symbolSize: CGFloat {
        #if os(tvOS)
        34
        #else
        20
        #endif
    }
}

private struct NumberPadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NumberPadButtonBody(configuration: configuration)
    }
}

private struct NumberPadButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(isFocused ? .continuumBackground : .continuumOnSurface)
            .frame(width: NumberPadButton.size, height: NumberPadButton.size)
            .background(background)
            .overlay(border)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            #if os(tvOS)
            .focusEffectDisabled()
            #endif
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
    }

    @ViewBuilder
    private var background: some View {
        #if os(tvOS)
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isFocused ? Color.continuumOnSurface : Color.white.opacity(0.1))
        #else
        Circle()
            .fill(Color.continuumSurfaceVariant)
        #endif
    }

    @ViewBuilder
    private var border: some View {
        #if os(tvOS)
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isFocused ? Color.clear : Color.white.opacity(0.18), lineWidth: 1)
        #else
        EmptyView()
        #endif
    }
}
