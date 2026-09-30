import SwiftUI

struct PlaybackStatsPanel: View {
    /// How the same row set is dressed. The rows themselves always come from
    /// `PlaybackStats`, so the platforms can't drift on *what* is reported —
    /// only on how much chrome is drawn around it.
    enum Layout {
        /// tvOS Info HUD pane: uppercase section headers, trailing-aligned
        /// label column, monospaced values. Reads as a panel.
        case sectioned
        /// iOS overlay: one flat `Label:  value` list, no section headers,
        /// drawn straight onto the picture. Reads as annotation.
        case plain
    }

    let stats: PlaybackStats
    var layout: Layout = .sectioned
    var usesTVTypography = false
    var usesTwoColumnLayout = false

    static let sourceSectionID = "stats-source"
    static let planSectionID = "stats-plan"
    static let eventsSectionID = "stats-events"
    static let mediaSectionID = "stats-media"
    static let bufferSectionID = "stats-buffer"
    static let networkSectionID = "stats-network"
    static let engineSectionID = "stats-engine"

    var body: some View {
        Group {
            switch layout {
            case .plain:
                plainList
            case .sectioned where usesTwoColumnLayout:
                HStack(alignment: .top, spacing: 34) {
                    column(leftSections)
                    divider
                    column(rightSections, includesEvents: true)
                }
            case .sectioned:
                column(allSections, includesEvents: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Plain layout

    /// Flat `Label:` / value grid over `compactRows`. Draws no background of
    /// its own — the overlay owns that, so this stays reusable as bare
    /// annotation. Single column by design: the compact set is short enough
    /// to fit a phone in landscape, which is what lets the overlay stay
    /// inert (no scrolling) without clipping anything.
    private var plainList: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(stats.compactRows, id: \.0) { row in
                GridRow {
                    Text("\(row.0):")
                        .foregroundStyle(.white.opacity(0.58))
                        .gridColumnAlignment(.leading)
                    Text(row.1)
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        // Plan and stream-path values run long; wrap them
                        // instead of widening the plate across the picture.
                        .frame(maxWidth: 320, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11))
    }

    /// Recent player events for the iOS overlay: `time  message`, newest
    /// first. Rendered beside or below `plainList` by the overlay.
    func plainEventList(limit: Int) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("Recent events")
                    .foregroundStyle(.white.opacity(0.58))
                    .gridCellColumns(2)
            }
            ForEach(stats.eventRows(limit: limit)) { row in
                GridRow {
                    Text(row.time)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.58))
                    Text(row.message)
                        .foregroundStyle(Self.eventColor(row.kind))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11))
    }

    static func eventColor(_ kind: PlaybackEventLog.Kind) -> Color {
        switch kind {
        case .info: return .white.opacity(0.95)
        case .warning: return Color(red: 1, green: 0.8, blue: 0.4)
        case .error: return Color(red: 1, green: 0.55, blue: 0.5)
        }
    }

    private var leftSections: [StatsSection] {
        [
            .init(id: Self.sourceSectionID, title: "Source", rows: stats.sourceRows),
            .init(id: Self.planSectionID, title: "Plan", rows: stats.planRows),
            .init(id: Self.mediaSectionID, title: "Media", rows: stats.mediaRows)
        ]
    }

    private var rightSections: [StatsSection] {
        [
            .init(id: Self.bufferSectionID, title: "Buffer", rows: stats.bufferRows),
            .init(id: Self.networkSectionID, title: "Network", rows: stats.networkRows),
            .init(id: Self.engineSectionID, title: "Engine", rows: stats.engineRows)
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

    private func column(_ sections: [StatsSection], includesEvents: Bool = false) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
            ForEach(sections) { section in
                rows(for: section)
            }
            if includesEvents {
                eventRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// "Recent events" section: timestamp in the label column, message in
    /// the value column. Row identity is positional because timestamps repeat.
    @ViewBuilder
    private var eventRows: some View {
        let events = stats.eventRows()
        if !events.isEmpty {
            GridRow {
                Text("RECENT EVENTS")
                    .font(headerFont)
                    .foregroundStyle(.white.opacity(0.52))
                    .gridColumnAlignment(.trailing)
                    .id(Self.eventsSectionID)
                Color.clear
                    .frame(height: 1)
            }
            ForEach(events) { row in
                GridRow {
                    Text(row.time)
                        .font(labelFont)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.74))
                    Text(row.message)
                        .font(valueFont)
                        .foregroundStyle(Self.eventColor(row.kind))
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                }
            }
        }
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
