import SwiftUI

/// Week navigator: prev/next chevrons around seven day buttons, plus a
/// "Today" shortcut when viewing another week. Day buttons show an
/// event-dot indicator and highlight the selected day.
struct CalendarWeekStrip: View {
    let week: CalendarWeek
    let selectedDay: Date
    let isCurrentWeek: Bool
    let hasEvents: (Date) -> Bool
    let onSelectDay: (Date) -> Void
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void

    #if os(tvOS)
    @FocusState private var focusedControl: StripControl?
    #endif

    var body: some View {
        HStack(spacing: stripSpacing) {
            chevronButton(systemImage: "chevron.left", control: .previous, action: onPreviousWeek)
                .accessibilityLabel("Previous week")

            HStack(spacing: dayButtonSpacing) {
                ForEach(week.days, id: \.self) { date in
                    CalendarDayButton(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDay),
                        isToday: Calendar.current.isDateInToday(date),
                        hasEvents: hasEvents(date),
                        isFocused: isFocused(.day(date)),
                        action: { onSelectDay(date) }
                    )
                    .applyStripFocus(self, control: .day(date))
                }
            }

            chevronButton(systemImage: "chevron.right", control: .next, action: onNextWeek)
                .accessibilityLabel("Next week")

            if !isCurrentWeek {
                Button("Today", action: onToday)
                    .font(todayFont)
                    .foregroundColor(isFocused(.today) ? .continuumBackground : .continuumOnSurface)
                    .buttonStyle(.continuumFlat)
                    .padding(.horizontal, todayHorizontalPadding)
                    .frame(height: chevronHeight)
                    .background(
                        Capsule().fill(
                            isFocused(.today)
                                ? Color.continuumOnSurface.opacity(0.94)
                                : Color.white.opacity(0.08)
                        )
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .applyStripFocus(self, control: .today)
                    .accessibilityLabel("Jump to today")
            }

            Spacer(minLength: 0)

            Text(monthLabel)
                .font(monthFont)
                .foregroundColor(.continuumSecondaryText)
        }
        .padding(.horizontal, ContinuumTheme.safePadding)
        #if os(tvOS)
        .focusSection()
        #endif
        .animation(ContinuumTheme.springAnimation, value: isCurrentWeek)
    }

    /// "June 2026" — uses the Thursday so a week spanning two months
    /// shows the month that owns most of its days.
    private var monthLabel: String {
        let anchor = Calendar.current.date(byAdding: .day, value: 3, to: week.startDate)
            ?? week.startDate
        return anchor.formatted(.dateTime.month(.wide).year())
    }

    private func chevronButton(
        systemImage: String,
        control: StripControl,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(chevronFont)
                .foregroundColor(
                    isFocused(control) ? .continuumBackground : .continuumOnSurface.opacity(0.7)
                )
                .frame(width: chevronWidth, height: chevronHeight)
                .background(
                    Circle().fill(
                        isFocused(control)
                            ? Color.continuumOnSurface.opacity(0.94)
                            : Color.white.opacity(0.08)
                    )
                )
        }
        .buttonStyle(.continuumFlat)
        .applyStripFocus(self, control: control)
    }

    // MARK: - Focus plumbing

    enum StripControl: Hashable {
        case previous
        case next
        case today
        case day(Date)
    }

    fileprivate func isFocused(_ control: StripControl) -> Bool {
        #if os(tvOS)
        return focusedControl == control
        #else
        return false
        #endif
    }

    #if os(tvOS)
    fileprivate var focusBinding: FocusState<StripControl?>.Binding { $focusedControl }
    #endif

    // MARK: - Metrics

    private var stripSpacing: CGFloat {
        #if os(tvOS)
        return 18
        #else
        return 8
        #endif
    }

    private var dayButtonSpacing: CGFloat {
        #if os(tvOS)
        return 10
        #else
        return 4
        #endif
    }

    private var chevronFont: Font {
        #if os(tvOS)
        return .system(size: 24, weight: .semibold)
        #else
        return .system(size: 13, weight: .semibold)
        #endif
    }

    private var chevronWidth: CGFloat {
        #if os(tvOS)
        return 64
        #else
        return 32
        #endif
    }

    private var chevronHeight: CGFloat {
        #if os(tvOS)
        return 64
        #else
        return 32
        #endif
    }

    private var todayFont: Font {
        #if os(tvOS)
        return .system(size: 22, weight: .semibold)
        #else
        return .system(size: 13, weight: .semibold)
        #endif
    }

    private var todayHorizontalPadding: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 12
        #endif
    }

    private var monthFont: Font {
        #if os(tvOS)
        return .system(size: 24, weight: .semibold)
        #else
        return .system(size: 13, weight: .semibold)
        #endif
    }
}

private extension View {
    /// tvOS: bind a strip control to the shared `@FocusState`; no-op on
    /// other platforms.
    @ViewBuilder
    func applyStripFocus(
        _ strip: CalendarWeekStrip,
        control: CalendarWeekStrip.StripControl
    ) -> some View {
        #if os(tvOS)
        self.focused(strip.focusBinding, equals: control)
        #else
        self
        #endif
    }
}

// MARK: - Day button

private struct CalendarDayButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasEvents: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: labelSpacing) {
                Text(weekdayLabel)
                    .font(weekdayFont)
                    .foregroundColor(secondaryColor)

                Text(dayNumber)
                    .font(numberFont)
                    .foregroundColor(primaryColor)

                Circle()
                    .fill(hasEvents ? dotColor : .clear)
                    .frame(width: dotSize, height: dotSize)
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius, style: .continuous)
                    .stroke(
                        isToday && !isSelected && !isFocused
                            ? Color.white.opacity(0.35)
                            : .clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
        }
        .buttonStyle(.continuumFlat)
        .animation(ContinuumTheme.springAnimation, value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var weekdayLabel: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var dayNumber: String {
        date.formatted(.dateTime.day())
    }

    private var accessibilityDescription: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            + (hasEvents ? ", has events" : "")
    }

    private var inverted: Bool { isSelected || isFocused }

    private var primaryColor: Color {
        inverted ? .continuumBackground : .continuumOnSurface
    }

    private var secondaryColor: Color {
        inverted ? Color.continuumBackground.opacity(0.7) : .continuumSecondaryText
    }

    private var dotColor: Color {
        inverted ? .continuumBackground : .continuumOnSurface.opacity(0.8)
    }

    private var backgroundFill: Color {
        if isFocused { return Color.continuumOnSurface.opacity(0.94) }
        if isSelected { return Color.continuumOnSurface.opacity(0.88) }
        return Color.white.opacity(0.05)
    }

    // MARK: - Metrics

    private var labelSpacing: CGFloat {
        #if os(tvOS)
        return 6
        #else
        return 3
        #endif
    }

    private var weekdayFont: Font {
        #if os(tvOS)
        return .system(size: 18, weight: .semibold)
        #else
        return .system(size: 10, weight: .semibold)
        #endif
    }

    private var numberFont: Font {
        #if os(tvOS)
        return .system(size: 26, weight: .bold)
        #else
        return .system(size: 15, weight: .bold)
        #endif
    }

    private var dotSize: CGFloat {
        #if os(tvOS)
        return 8
        #else
        return 4
        #endif
    }

    private var buttonWidth: CGFloat {
        #if os(tvOS)
        return 84
        #else
        return 42
        #endif
    }

    private var buttonHeight: CGFloat {
        #if os(tvOS)
        return 96
        #else
        return 56
        #endif
    }
}
