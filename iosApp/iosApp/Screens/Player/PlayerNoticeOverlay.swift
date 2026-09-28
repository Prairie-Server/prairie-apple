import Foundation
import SwiftUI

enum PlayerNoticeTone {
    case info
    case warning

    var accentColor: Color {
        switch self {
        case .info:
            return .prairiePrimary
        case .warning:
            return .prairieWarning
        }
    }
}

struct PlayerNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let tone: PlayerNoticeTone
}

struct PlayerNoticeOverlay: View {
    let notice: PlayerNotice

    var body: some View {
        HStack(spacing: PrairieTheme.spacing) {
            Circle()
                .fill(notice.tone.accentColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: PrairieTheme.smallPadding) {
                Text(notice.title)
                    .font(.prairieSubheadline)
                    .foregroundColor(.prairieOnSurface)

                Text(notice.message)
                    .font(.prairieBody)
                    .foregroundColor(.prairieSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PrairieTheme.padding)
        .padding(.vertical, PrairieTheme.spacing)
        .frame(maxWidth: 720)
        .prairiePlayerGlass(
            in: RoundedRectangle(
                cornerRadius: PrairieTheme.cardCornerRadius,
                style: .continuous
            ),
            tint: notice.tone.accentColor.opacity(0.28)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .padding(.horizontal, PrairieTheme.safePadding)
        .padding(.top, PrairieTheme.safePadding)
        .transition(
            .move(edge: .top)
            .combined(with: .opacity)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notice.title). \(notice.message)")
    }
}
