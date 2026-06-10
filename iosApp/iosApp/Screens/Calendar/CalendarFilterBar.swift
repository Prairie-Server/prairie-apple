import SwiftUI

/// Segmented Following / Trending / All preset control. Capsule segments
/// matching the app's monochrome pill language; on tvOS each segment
/// draws its own focus chrome (the app suppresses the system slab).
struct CalendarFilterBar: View {
    let selected: CalendarFilter
    let onSelect: (CalendarFilter) -> Void
    /// tvOS: programmatic focus kick from the root focus hand-down, so
    /// the remote is never dead when the Calendar tab swaps in.
    var focusRequest: Int = 0
    /// tvOS: edge-up escape back to the top menu bar.
    var onMoveUp: (() -> Void)? = nil

    @FocusState private var focusedFilter: CalendarFilter?
    #if os(tvOS)
    /// Each hand-down token claims focus exactly once; guards against
    /// `onAppear` re-fires yanking focus on scroll recycling.
    @State private var lastAppliedFocusRequest = 0
    #endif

    var body: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(CalendarFilter.allCases) { filter in
                segmentButton(filter)
            }
        }
        .padding(containerPadding)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        #if os(tvOS)
        .focusSection()
        .onMoveCommand { direction in
            if direction == .up {
                onMoveUp?()
            }
        }
        .onAppear { applyFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
        #endif
    }

    #if os(tvOS)
    private func applyFocusRequest(_ request: Int) {
        guard request > 0, request != lastAppliedFocusRequest else { return }
        lastAppliedFocusRequest = request
        focusedFilter = selected
    }
    #endif

    private func segmentButton(_ filter: CalendarFilter) -> some View {
        let isSelected = selected == filter
        let isFocused = focusedFilter == filter

        return Button {
            onSelect(filter)
        } label: {
            Text(filter.displayLabel)
                .font(segmentFont)
                .lineLimit(1)
                .foregroundColor(foreground(isSelected: isSelected, isFocused: isFocused))
                .padding(.horizontal, segmentHorizontalPadding)
                .frame(height: segmentHeight)
                .background(
                    Capsule().fill(fill(isSelected: isSelected, isFocused: isFocused))
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedFilter, equals: filter)
        .animation(ContinuumTheme.springAnimation, value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func foreground(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused || isSelected { return .continuumBackground }
        return .continuumOnSurface.opacity(0.7)
    }

    private func fill(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused { return Color.continuumOnSurface.opacity(0.96) }
        if isSelected { return Color.continuumOnSurface.opacity(0.88) }
        return .clear
    }

    // MARK: - Metrics

    private var segmentSpacing: CGFloat {
        #if os(tvOS)
        return 6
        #else
        return 2
        #endif
    }

    private var containerPadding: CGFloat {
        #if os(tvOS)
        return 6
        #else
        return 3
        #endif
    }

    private var segmentFont: Font {
        #if os(tvOS)
        return .system(size: 22, weight: .semibold)
        #else
        return .system(size: 13, weight: .semibold)
        #endif
    }

    private var segmentHorizontalPadding: CGFloat {
        #if os(tvOS)
        return 26
        #else
        return 14
        #endif
    }

    private var segmentHeight: CGFloat {
        #if os(tvOS)
        return 54
        #else
        return 28
        #endif
    }
}
