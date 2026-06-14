#if os(tvOS)
import SwiftUI

/// First-run server entry on tvOS (Aurora). Two paths side by side over the
/// aurora backdrop: a "Continue on iPhone" handoff card (stubbed until the
/// server pairing endpoint exists) and a fully functional manual-entry card.
/// The manual card is the emphasized, default-focused path.
struct TVServerSetupView: View {
    var router: AppRouter

    @State private var viewModel = ServerSetupViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case host
        case scheme(ServerSetupScheme)
        case port
        case connect
    }

    var body: some View {
        ZStack {
            AuroraBackdrop(variant: .server, scrim: .soft)
            content
                .padding(.horizontal, 96)
                .padding(.top, 64)
                .padding(.bottom, 64)
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 20)
            VStack(spacing: 14) {
                AuroraEyebrow(text: "Step 01 — Connect", centered: true)
                Text("Add your server")
                    .font(.auroraSerif(52, .semibold))
                    .foregroundStyle(Color.auroraInk)
            }
            Spacer(minLength: 36)
            HStack(alignment: .center, spacing: 0) {
                phoneCard
                    .frame(width: 600)
                orDivider
                    .frame(width: 84)
                manualCard
                    .frame(width: 600)
                    .focusSection()
            }
            .frame(height: 580)
            Spacer(minLength: 0)
        }
        .defaultFocus($focusedField, .host, priority: .userInitiated)
    }

    private var topBar: some View {
        HStack {
            SiloWordmarkView(width: 132)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Phone handoff card (coming soon)

    private var phoneCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            comingSoonPill
            Spacer(minLength: 28)
            Image(systemName: "iphone.gen3")
                .font(.system(size: 76, weight: .ultraLight))
                .foregroundStyle(Color.auroraInkSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 28)
            Text("Continue on iPhone")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.auroraInk)
            Text("Set this Apple TV up from your phone in a tap — the address and your account come across automatically. Arriving in a future update.")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.auroraInkSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(46)
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraGlass(cornerRadius: 28)
        .opacity(0.62)
    }

    private var comingSoonPill: some View {
        Text("COMING SOON")
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(Color.auroraInkSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: - OR divider

    private var orDivider: some View {
        VStack(spacing: 16) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Text("OR")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color.auroraInkTertiary)
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Manual entry card (active)

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Enter it here")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.auroraInk)

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Server address")
                AuroraInputField(
                    text: $viewModel.host,
                    placeholder: "media.example.com",
                    focus: $focusedField,
                    equals: .host,
                    contentType: .URL,
                    keyboard: .URL
                )
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Protocol")
                    protocolSegments
                }
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Port")
                    AuroraInputField(
                        text: $viewModel.port,
                        placeholder: "8096",
                        focus: $focusedField,
                        equals: .port,
                        keyboard: .numberPad
                    )
                }
                .frame(width: 190)
            }

            if let error = viewModel.error {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.continuumError)
                    Text(error)
                        .font(.continuumCaption)
                        .foregroundStyle(Color.continuumError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            Button {
                guard !viewModel.isLoading else { return }
                Task { await viewModel.connect(router: router) }
            } label: {
                Text(viewModel.isLoading ? "Connecting…" : "Connect")
            }
            .buttonStyle(AuroraPrimaryButtonStyle(isLoading: viewModel.isLoading))
            .focused($focusedField, equals: .connect)
        }
        .padding(46)
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraGlass(cornerRadius: 28, emphasized: true)
        .animation(.easeInOut(duration: 0.2), value: viewModel.error)
    }

    private var protocolSegments: some View {
        HStack(spacing: 8) {
            ForEach(ServerSetupScheme.allCases) { scheme in
                Button {
                    viewModel.selectedScheme = scheme
                } label: {
                    AuroraSegment(
                        title: scheme.rawValue,
                        isSelected: viewModel.selectedScheme == scheme,
                        isFocused: focusedField == .scheme(scheme)
                    )
                }
                .buttonStyle(.continuumFlat)
                .focused($focusedField, equals: .scheme(scheme))
            }
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(Color.auroraInkTertiary)
    }
}

#endif
