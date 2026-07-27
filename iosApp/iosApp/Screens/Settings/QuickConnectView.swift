import SwiftUI

/// Settings → Quick Connect: enter the code shown on another Prairie client
/// and approve or deny the pending sign-in.
struct QuickConnectView: View {
    @State private var viewModel = QuickConnectViewModel()

    var body: some View {
        Form {
            Section {
                TextField("ABCD-EFGH", text: $viewModel.codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .disabled(viewModel.phase != .enterCode && viewModel.phase != .loading)
                    .onChange(of: viewModel.codeInput) { _, newValue in
                        let normalized = QuickConnectViewModel.normalizeCode(newValue)
                        if normalized != newValue {
                            viewModel.codeInput = normalized
                        }
                    }

                Button("Continue", systemImage: "arrow.right") {
                    Task { await viewModel.lookupDevice() }
                }
                .disabled(!viewModel.canLookup || viewModel.phase == .loading)
            } header: {
                Text("Device code")
            } footer: {
                Text("Enter the Quick Connect code shown on the TV, Roku, Smart TV, or web login screen.")
            }

            if viewModel.phase == .loading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Looking up device…")
                            .foregroundStyle(Color.continuumSecondaryText)
                    }
                }
            }

            if let lookup = viewModel.lookup, viewModel.phase != .enterCode {
                Section("Device") {
                    LabeledContent("Name", value: lookup.deviceName ?? "Unknown device")
                    if let platform = lookup.devicePlatform, !platform.isEmpty {
                        LabeledContent("Platform", value: platform)
                    }
                    if let ip = lookup.ipAddressHint, !ip.isEmpty {
                        LabeledContent("IP", value: ip)
                    }
                    if let match = lookup.matchCode, !match.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Match code")
                                .font(.caption)
                                .foregroundStyle(Color.continuumSecondaryText)
                            Text(match)
                                .font(.title3.weight(.semibold))
                            Text("Confirm this phrase matches the other screen before approving.")
                                .font(.footnote)
                                .foregroundStyle(Color.continuumSecondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if case .ready = viewModel.phase {
                Section {
                    Button("Approve sign-in", systemImage: "checkmark") {
                        Task { await viewModel.approve() }
                    }
                    .disabled(!viewModel.canDecide)
                    Button("Deny", systemImage: "xmark", role: .destructive) {
                        Task { await viewModel.deny() }
                    }
                    .disabled(!viewModel.canDecide)
                }
            }

            if case let .completed(approved) = viewModel.phase {
                Section {
                    Text(approved ? "Approved. Finish sign-in on the other device." : "This sign-in request was denied.")
                    Button("Enter another code", systemImage: "arrow.counterclockwise") {
                        viewModel.reset()
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("How it works") {
                Text("1. On the other device, choose Quick Connect on the sign-in screen.")
                Text("2. Enter the displayed code here and confirm the match phrase.")
                Text("3. Approve — the other device signs in automatically.")
            }
        }
        .navigationTitle("Quick Connect")
        .continuumNavigationTitleDisplayMode(.inline)
    }
}
