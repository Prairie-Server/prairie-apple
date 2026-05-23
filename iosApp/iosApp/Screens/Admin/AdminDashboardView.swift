import SwiftUI

/// Admin dashboard showing server stats.
struct AdminDashboardView: View {
    @State private var viewModel = AdminViewModel()
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let stats = viewModel.stats {
                statsContent(stats: stats)
            } else if let error = viewModel.error {
                ErrorView(state: error, onRetry: { Task { await viewModel.loadStats() } })
            } else if viewModel.isLoading {
                Color.clear
            }
        }
        .continuumBackground()
        .navigationTitle("Admin")
        .continuumNavigationTitleDisplayMode(.large)
        .task {
            await viewModel.loadStats()
        }
        .refreshable {
            await viewModel.loadStats()
        }
    }

    // MARK: - Stats Content

    private func statsContent(stats: AdminStats) -> some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                statCard(title: "Total Items", value: "\(stats.totalItems ?? 0)", icon: "film.stack", color: .continuumPrimary)
                statCard(title: "Users", value: "\(stats.totalUsers ?? 0)", icon: "person.2", color: .continuumSuccess)
                statCard(title: "Movies", value: "\(stats.totalMovies ?? 0)", icon: "film", color: .continuumWarning)
                statCard(title: "TV Shows", value: "\(stats.totalShows ?? 0)", icon: "tv", color: .continuumPrimaryLight)
                statCard(title: "Active Streams", value: "\(stats.activeStreams ?? 0)", icon: "play.circle", color: .continuumError)
                statCard(title: "Storage", value: formatBytes(stats.totalStorageBytes ?? 0), icon: "externaldrive", color: .continuumSecondaryText)
            }
            .padding(ContinuumTheme.padding)
        }
    }

    // MARK: - Stat Card

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.continuumTitle)
                .foregroundColor(.continuumOnSurface)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(title)
                .font(.continuumCaption)
                .foregroundColor(.continuumSecondaryText)
        }
        .padding(ContinuumTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                .fill(Color.continuumSurface)
        )
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = Double(bytes) / (1024 * 1024 * 1024 * 1024)
        if tb >= 1.0 {
            return String(format: "%.1f TB", tb)
        }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}
