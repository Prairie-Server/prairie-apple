#if os(tvOS)
import SwiftUI
import UIKit

/// Split-panel sign-in for tvOS. The left column is a compact
/// username/password form; the right column renders a live QR pairing
/// code so users on a remote can skip typing entirely. A device-login
/// session is started eagerly on appear so the QR is scannable the
/// moment the screen becomes visible.
struct TVLoginView: View {
    var router: AppRouter

    @State private var loginVM = LoginViewModel()
    @State private var qrVM = QRLoginViewModel()
    @State private var showPassword: Bool = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username
        case password
        case togglePassword
        case signIn
        case changeServer
    }

    var body: some View {
        ZStack {
            background
            content
                .padding(.horizontal, 96)
                .padding(.top, 64)
                .padding(.bottom, 56)
        }
        .task {
            await qrVM.begin(
                deviceName: Self.deviceName,
                devicePlatform: "tvOS"
            )
        }
        .onChange(of: qrVM.state) { _, newValue in
            if case .approved = newValue {
                router.showProfileSelection()
            }
        }
        .onDisappear { qrVM.cancel() }
        .ignoresSafeArea()
    }

    // MARK: - Background

    private var background: some View {
        Color.continuumBackground.ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 44)
            HStack(alignment: .top, spacing: 44) {
                signInPanel
                    .frame(width: 540, alignment: .leading)
                divider
                qrPanel
                    .frame(width: 620, alignment: .leading)
            }
            .frame(maxWidth: 1248)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Top bar (wordmark + Change Server chip)

    private var topBar: some View {
        HStack(alignment: .center) {
            wordmark
            Spacer(minLength: 0)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 18) {
            SiloWordmarkView(width: 132)
            if let host = hostLabel {
                Text(host)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
        }
    }

    private var changeServerChip: some View {
        Button {
            router.resetToServerSetup()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
                Text("Change Server")
                    .font(.system(size: 18, weight: .medium))
            }
        }
        .buttonStyle(ContinuumTextButtonStyle())
        .focused($focusedField, equals: .changeServer)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    // MARK: - Sign-in panel (left column)

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign In")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Enter your credentials to continue.")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.bottom, 4)

            fieldGroup(label: "USERNAME") {
                TextField("yourname", text: $loginVM.username)
                    .modifier(TVAuthFieldChrome(isFocused: focusedField == .username))
                    .focused($focusedField, equals: .username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            fieldGroup(label: "PASSWORD") {
                HStack(spacing: 12) {
                    Group {
                        if showPassword {
                            TextField("••••••", text: $loginVM.password)
                        } else {
                            SecureField("••••••", text: $loginVM.password)
                        }
                    }
                    .modifier(TVAuthFieldChrome(isFocused: focusedField == .password))
                    .focused($focusedField, equals: .password)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 22, weight: .medium))
                    }
                    .buttonStyle(TVAuthIconButtonStyle())
                    .focused($focusedField, equals: .togglePassword)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
            }

            if let error = loginVM.error {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.continuumError)
                    Text(error)
                        .font(.continuumCaption)
                        .foregroundStyle(Color.continuumError)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            Button {
                Task { await loginVM.login(router: router) }
            } label: {
                Text(loginVM.isLoading ? "Signing in…" : "Sign In")
            }
            .buttonStyle(ContinuumPrimaryButtonStyle(isLoading: loginVM.isLoading))
            .focused($focusedField, equals: .signIn)
            .disabled(loginVM.isLoading)

            // Change Server lives at the bottom of the form column —
            // focus can D-pad Down from Sign In to reach it, and Up
            // back to Sign In. Placing it top-right previously created
            // an unreachable corner: from Change Server there was no
            // focus target directly below (right column has no
            // focusables), so D-pad Down dead-ended on the chip.
            HStack {
                Spacer()
                changeServerChip
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                .fill(Color.continuumSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: loginVM.error)
        .focusSection()
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.capitalized)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
            content()
        }
    }

    // MARK: - QR panel (right column)

    private var qrPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Phone sign in")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("Scan the QR code, confirm the code, then approve.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            }

            qrBody
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                .fill(Color.continuumSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var qrBody: some View {
        switch qrVM.state {
        case .idle, .starting:
            qrPlaceholder
        case .awaiting(let session):
            qrActive(session: session)
        case .approved:
            qrApproved
        case .error(let message):
            qrError(message: message)
        }
    }

    /// Pre-session shimmer — placeholder card while the device-login
    /// handshake is in flight. Keeps the QR column from popping in late.
    private var qrPlaceholder: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer(minLength: 0)
                qrCardContainer {
                    ZStack {
                        Color.white.opacity(0.04)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                            .scaleEffect(1.2)
                    }
                    .frame(width: Self.qrSize, height: Self.qrSize)
                }
                Spacer(minLength: 0)
            }
            Text("Preparing a pairing code…")
                .font(.continuumBody)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func qrActive(session: DeviceLoginStartResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer(minLength: 0)
                qrCardContainer {
                    QRCodeView(content: session.verificationUriComplete, size: Self.qrSize)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 22) {
                qrInstructions(session: session)
                VStack(alignment: .leading, spacing: 14) {
                    matchCodeBlock(session.matchCode)
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func qrCardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private func qrInstructions(session: DeviceLoginStartResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            qrStep(number: "1", text: "Scan this code with your phone camera")
            qrStep(number: "2", text: "Sign in on your phone if prompted")
            qrStep(number: "3", text: "Confirm the code matches below, then approve")
            Text("Or visit \(session.verificationUri) and enter \(session.userCode)")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private func qrStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.85)))
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func matchCodeBlock(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verify this matches")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(code)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                .scaleEffect(0.8)
            Text(statusText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
        }
    }

    private var qrApproved: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.green)
            Text("Approved — signing you in…")
                .font(.continuumSubheadline)
                .foregroundStyle(.white)
        }
    }

    private func qrError(message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.continuumError)
                Text("Pairing code unavailable")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.continuumCaption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await qrVM.retry() }
            }
            .buttonStyle(ContinuumSecondaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Computed helpers

    /// "yourserver.local" pulled out of the stored URL. Grounds the screen
    /// so the user knows exactly which server they're signing into without
    /// needing a full URL on display.
    private var hostLabel: String? {
        let url = AuthService.shared.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        if let parsed = URL(string: url), let host = parsed.host, !host.isEmpty {
            return host
        }
        return url.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    private var statusText: String {
        let remaining = qrVM.secondsRemaining
        guard remaining > 0 else { return "Waiting for approval…" }
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "Waiting for approval · %d:%02d", minutes, seconds)
    }

    // MARK: - Constants

    /// Large enough to scan comfortably while keeping the login screen
    /// inside the visible tvOS safe area.
    private static let qrSize: CGFloat = 300

    private static var deviceName: String {
        let name = UIDevice.current.name
        return name.isEmpty ? "Apple TV" : name
    }
}

// MARK: - Field chrome

/// Explicit focus-aware chrome for tvOS text fields. We can't rely on
/// `ContinuumTextFieldStyle` here because `@Environment(\.isFocused)`
/// inside a `TextFieldStyle._body` doesn't reliably fire for SwiftUI
/// TextFields on tvOS — the focus platter paints but the style's text
/// color flip never runs, so the typed value ends up white-on-white and
/// unreadable. Taking focus as an explicit parameter from the owning
/// view's `@FocusState` sidesteps the issue entirely.
struct TVAuthFieldChrome: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.continuumBody)
            .foregroundStyle(isFocused ? Color.continuumBackground : Color.continuumOnSurface)
            .tint(isFocused ? Color.continuumBackground : Color.continuumOnSurface)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .continuumInputChrome(isFocused: isFocused)
    }
}

// MARK: - Local button styles

/// Square icon-only focus affordance for the password show/hide toggle.
/// Lives next to the password field and mirrors the field's focus
/// treatment (dark fill at rest, white on focus) so the row reads as a
/// single control.
private struct TVAuthIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVAuthIconButtonBody(configuration: configuration)
    }
}

private struct TVAuthIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.continuumBackground : Color.white.opacity(0.7))
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                    .fill(isFocused ? Color.continuumOnSurface : Color.continuumSurfaceVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                            .stroke(
                                isFocused ? Color.clear : Color.continuumOutline,
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
    }
}

#endif
