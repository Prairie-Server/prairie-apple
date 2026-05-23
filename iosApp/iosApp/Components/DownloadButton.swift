import SwiftUI

/// Button for initiating a download. Currently a stub.
struct DownloadButton: View {
    enum DownloadState {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
    }

    let state: DownloadState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch state {
                case .notDownloaded:
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.continuumSecondaryText)

                case .downloading(let progress):
                    ZStack {
                        Circle()
                            .stroke(Color.continuumSecondaryText.opacity(0.3), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.continuumPrimary, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 22, height: 22)

                case .downloaded:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.continuumSuccess)
                }
            }
            .font(.system(size: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download")
    }
}
