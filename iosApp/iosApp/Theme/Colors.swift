import SwiftUI

extension Color {
    // MARK: - Core Palette (Plezy OLED Dark)

    /// Pure black background (#000000)
    static let continuumBackground = Color(hex: "#000000")

    /// Barely-visible surface (#0A0A0A)
    static let continuumSurface = Color(hex: "#0A0A0A")

    /// Surface variant for containers (#0E0F12)
    static let continuumSurfaceVariant = Color(hex: "#0E0F12")

    /// Surface for elevated containers like episode cards (#15171C)
    static let continuumSurfaceElevated = Color(hex: "#15171C")

    /// Primary interactive color — same as text (monochrome UI)
    static let continuumPrimary = Color(hex: "#EDEDED")

    /// Kept for backwards compat — same as primary
    static let continuumPrimaryLight = Color(hex: "#EDEDED")

    /// Primary text color (#EDEDED)
    static let continuumOnSurface = Color(hex: "#EDEDED")

    /// Muted/secondary text — primary at 60% opacity (#99EDEDED)
    static let continuumSecondaryText = Color(hex: "#99EDEDED")

    /// Error red (#B00020)
    static let continuumError = Color(hex: "#B00020")

    /// Success green
    static let continuumSuccess = Color.green

    /// Warning amber (ratings stars)
    static let continuumWarning = Color(hex: "#FFC107")

    // MARK: - Semantic Aliases

    /// Outline/border color — white at 12%
    static let continuumOutline = Color.white.opacity(0.12)

    /// Overlay for sheets and modals
    static let continuumOverlay = Color.black.opacity(0.6)

    /// Divider/separator line color — white at 12%
    static let continuumDivider = Color.white.opacity(0.12)

    /// Disabled control tint
    static let continuumDisabled = Color(hex: "#4B5563")
}
