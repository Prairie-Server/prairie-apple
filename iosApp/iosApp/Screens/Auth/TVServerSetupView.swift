#if os(tvOS)
import SwiftUI

/// First-run server URL entry on tvOS. A single centered card on the
/// same radial-spotlight canvas as `TVLoginView` / `ProfileSelectionView`,
/// so the pre-auth flow reads as one continuous environment as the user
/// moves through server → login → profile.
struct TVServerSetupView: View {
    var router: AppRouter

    @State private var viewModel = ServerSetupViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case host
        case advanced
        case scheme(ServerSetupScheme)
        case port
        case connect
    }

    var body: some View {
        ZStack {
            background
            content
        }
        .ignoresSafeArea()
    }

    // MARK: - Background

    private var background: some View {
        Color.continuumBackground.ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            authHeader
            Spacer(minLength: 76)
            formCard
                .frame(maxWidth: 760)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ContinuumTheme.safePadding)
        .padding(.top, 88)
        .padding(.bottom, 72)
    }

    // MARK: - Header

    private var authHeader: some View {
        HStack {
            SiloWordmarkView(width: 132, subtitle: "Server setup")
            Spacer(minLength: 0)
        }
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Server")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Enter the host for your Silo server.")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Server host")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))

                TextField("media.example.com", text: $viewModel.host)
                    .modifier(TVAuthFieldChrome(isFocused: focusedField == .host))
                    .focused($focusedField, equals: .host)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            VStack(alignment: .leading, spacing: 16) {
                Button {
                    viewModel.showsAdvancedOptions.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.showsAdvancedOptions ? "chevron.down" : "chevron.right")
                            .font(.system(size: 18, weight: .bold))
                        Text("Advanced")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundStyle(focusedField == .advanced ? Color.continuumBackground : .white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .continuumInputChrome(isFocused: focusedField == .advanced)
                }
                .buttonStyle(.continuumFlat)
                .focused($focusedField, equals: .advanced)

                if viewModel.showsAdvancedOptions {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Protocol")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.66))

                            HStack(spacing: 12) {
                                ForEach(ServerSetupScheme.allCases) { scheme in
                                    Button {
                                        viewModel.selectedScheme = scheme
                                    } label: {
                                        Text(scheme.rawValue)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(protocolTextColor(for: scheme))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(protocolBackground(for: scheme))
                                    }
                                    .buttonStyle(.continuumFlat)
                                    .focused($focusedField, equals: .scheme(scheme))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Port")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.66))

                            TextField("Optional", text: $viewModel.port)
                                .modifier(TVAuthFieldChrome(isFocused: focusedField == .port))
                                .focused($focusedField, equals: .port)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numberPad)
                        }
                    }
                    .transition(.opacity)
                }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            Button {
                guard !viewModel.isLoading else { return }
                Task { await viewModel.connect(router: router) }
            } label: {
                Text(viewModel.isLoading ? "Connecting…" : "Connect")
            }
            .buttonStyle(ContinuumPrimaryButtonStyle(isLoading: viewModel.isLoading))
            .focused($focusedField, equals: .connect)
            // Stay focusable while connecting so focus isn't bounced to a
            // neighbour mid-request; re-entry is guarded above.
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 44)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                .fill(Color.continuumSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.error)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showsAdvancedOptions)
        .focusSection()
        // Land first focus on the address field rather than whatever the engine
        // picks geometrically — this is the first screen a new user sees.
        .defaultFocus($focusedField, .host, priority: .userInitiated)
    }

    private func protocolTextColor(for scheme: ServerSetupScheme) -> Color {
        if focusedField == .scheme(scheme) {
            return .continuumBackground
        }
        return viewModel.selectedScheme == scheme ? .continuumOnSurface : .white.opacity(0.64)
    }

    private func protocolBackground(for scheme: ServerSetupScheme) -> some View {
        let isFocused = focusedField == .scheme(scheme)
        let isSelected = viewModel.selectedScheme == scheme
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isFocused ? Color.white : Color.white.opacity(isSelected ? 0.16 : 0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isFocused || isSelected ? 0.45 : 0.1), lineWidth: 1)
            )
    }

}

#endif
