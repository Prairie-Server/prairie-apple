import SwiftUI

struct PlaybackStatsPanel: View {
    let stats: PlaybackStats
    var usesTVTypography = false
    var usesTwoColumnLayout = false

    static let sourceSectionID = "stats-source"
    static let mediaSectionID = "stats-media"
    static let bufferSectionID = "stats-buffer"
    static let networkSectionID = "stats-network"
    static let deviceSectionID = "stats-device"

    var body: some View {
        Group {
            if usesTwoColumnLayout {
                HStack(alignment: .top, spacing: 34) {
                    column(leftSections)
                    divider
                    column(rightSections)
                }
            } else {
                column(allSections)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leftSections: [StatsSection] {
        [
            .init(id: Self.sourceSectionID, title: "Source", rows: stats.sourceRows),
            .init(id: Self.mediaSectionID, title: "Media", rows: stats.mediaRows)
        ]
    }

    private var rightSections: [StatsSection] {
        [
            .init(id: Self.bufferSectionID, title: "Buffer", rows: stats.bufferRows),
            .init(id: Self.networkSectionID, title: "Network", rows: stats.networkRows),
            .init(id: Self.deviceSectionID, title: "Device", rows: stats.deviceRows)
        ]
    }

    private var allSections: [StatsSection] {
        leftSections + rightSections
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func column(_ sections: [StatsSection]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
            ForEach(sections) { section in
                rows(for: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func rows(for section: StatsSection) -> some View {
        if !section.rows.isEmpty {
            GridRow {
                Text(section.title.uppercased())
                    .font(headerFont)
                    .foregroundStyle(.white.opacity(0.52))
                    .gridColumnAlignment(.trailing)
                    .id(section.id)
                Color.clear
                    .frame(height: 1)
            }
            ForEach(section.rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(labelFont)
                        .foregroundStyle(.white.opacity(0.74))
                    Text(row.1)
                        .font(valueFont)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }
        }
    }

    private var headerFont: Font {
        usesTVTypography
            ? .system(size: 13, weight: .semibold)
            : .caption.weight(.semibold)
    }

    private var labelFont: Font {
        usesTVTypography
            ? .system(size: 20, weight: .medium)
            : .callout.weight(.medium)
    }

    private var valueFont: Font {
        usesTVTypography
            ? .system(size: 20, weight: .regular)
            : .callout.monospacedDigit()
    }

    private struct StatsSection: Identifiable {
        let id: String
        let title: String
        let rows: [(String, String)]
    }
}
