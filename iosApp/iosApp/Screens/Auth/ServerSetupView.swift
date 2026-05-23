import SwiftUI

/// First screen a user sees when no server URL is configured.
struct ServerSetupView: View {
    var router: AppRouter
    @State private var viewModel = ServerSetupViewModel()

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                SiloWordmarkView(width: 150, subtitle: "Media Server")

                Spacer()

                // Connection form
                VStack(spacing: ContinuumTheme.padding) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server Host")
                            .font(.continuumCaption)
                            .foregroundColor(.continuumSecondaryText)

                        TextField("media.example.com", text: $viewModel.host)
                            .textFieldStyle(ContinuumTextFieldStyle())
                            #if !os(macOS)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }

                    #if !os(tvOS)
                    advancedOptions
                    #endif

                    if let error = viewModel.error {
                        Text(error)
                            .font(.continuumCaption)
                            .foregroundColor(.continuumError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Connect") {
                        Task { await viewModel.connect(router: router) }
                    }
                    .buttonStyle(ContinuumPrimaryButtonStyle(isLoading: viewModel.isLoading))
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, ContinuumTheme.largePadding)
                .continuumFormWidth()

                Spacer()
            }
        }
    }

    #if !os(tvOS)
    private var advancedOptions: some View {
        DisclosureGroup(
            isExpanded: $viewModel.showsAdvancedOptions,
            content: {
                VStack(alignment: .leading, spacing: ContinuumTheme.padding) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Protocol")
                            .font(.continuumCaption)
                            .foregroundColor(.continuumSecondaryText)

                        Picker("Protocol", selection: $viewModel.selectedScheme) {
                            ForEach(ServerSetupScheme.allCases) { scheme in
                                Text(scheme.rawValue).tag(scheme)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Port")
                            .font(.continuumCaption)
                            .foregroundColor(.continuumSecondaryText)

                        TextField("Optional", text: $viewModel.port)
                            .textFieldStyle(ContinuumTextFieldStyle())
                            #if !os(macOS)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                .padding(.top, 8)
            },
            label: {
                Text("Advanced")
                    .font(.continuumCaption)
                    .foregroundColor(.continuumSecondaryText)
            }
        )
        .tint(.continuumSecondaryText)
    }
    #endif
}
