#if os(iOS)
import SwiftUI

struct DiagnosticsPromptSheet: View {
    let prompt: DiagnosticsPrompt
    @Bindable var model: DiagnosticsViewModel

    @State private var showAlwaysConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(prompt.message)
                }

                Section {
                    NavigationLink {
                        DiagnosticsPromptReviewView(prompt: prompt, model: model)
                    } label: {
                        Label("View Report", systemImage: "eye")
                    }

                    Button("Send", systemImage: "paperplane.fill") {
                        Task { await model.sendPrompt(always: false) }
                    }
                    .disabled(model.isWorking)

                    Button("Always Send", systemImage: "paperplane.circle.fill") {
                        showAlwaysConfirmation = true
                    }
                    .disabled(model.isWorking)
                    .confirmationDialog(
                        "Always Send Crash Reports?",
                        isPresented: $showAlwaysConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Always Send") {
                            Task { await model.sendPrompt(always: true) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This report and future crash reports for this server account will be sent automatically.")
                    }

                    Button("Don't Send", systemImage: "nosign", role: .cancel, action: model.declinePrompt)
                        .disabled(model.isWorking)
                }

                if model.isWorking {
                    ProgressView("Sending diagnostics…")
                }
            }
            .continuumGroupedListStyle()
            .navigationTitle(prompt.title)
        }
    }
}
#endif
