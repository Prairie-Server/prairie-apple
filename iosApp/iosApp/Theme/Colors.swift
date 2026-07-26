import SwiftUI

extension Color {
    // MARK: - Core Palette (Prairie Dusk)
    //
    // Mirrors prairie-server Phase 3 / prairie-smarttv tokens:
    // deep slate surfaces + amber wheat accent (#e0a84a).

    /// Deep slate background (#141820)
    static let continuumBackground = Color(hex: "#141820")

    /// Elevated surface (#1c222c)
    static let continuumSurface = Color(hex: "#1C222C")

    /// Surface variant for containers (#0e1116 sidebar tone)
    static let continuumSurfaceVariant = Color(hex: "#0E1116")

    /// Surface for elevated containers (#222B38)
    static let continuumSurfaceElevated = Color(hex: "#222B38")

    /// Primary interactive / brand accent — amber wheat
    static let continuumPrimary = Color(hex: "#E0A84A")

    /// Kept for backwards compat — same as primary
    static let continuumPrimaryLight = Color(hex: "#E0A84A")

    /// Primary text color (#F2EEE6)
    static let continuumOnSurface = Color(hex: "#F2EEE6")

    /// Accent for enabled control states (toggles, prominent buttons).
    static let continuumAccent = Color(hex: "#E0A84A")

    /// Brand accent for wordmark / first-run moments (same amber as dusk primary).
    static let continuumBrandOrange = Color(hex: "#E0A84A")

    /// Muted/secondary text (#9AA3B2)
    static let continuumSecondaryText = Color(hex: "#9AA3B2")

    /// Error red (#B00020)
    static let continuumError = Color(hex: "#B00020")

    /// Success green
    static let continuumSuccess = Color.green

    /// Warning amber (ratings stars)
    static let continuumWarning = Color(hex: "#FFC107")

    // MARK: - Skyline chrome (guide §4)

    /// Selected-but-unfocused tab/pill capsule fill — warm ink @ 14%
    static let continuumChromeSelectedFill = Color.continuumOnSurface.opacity(0.14)

    /// Inner border of the selected capsule
    static let continuumChromeSelectedBorder = Color.continuumOnSurface.opacity(0.10)

    /// Resting pill/chip fill
    static let continuumChromeRestingFill = Color.continuumOnSurface.opacity(0.07)

    /// Hairline border on resting pills/chips
    static let continuumChromeRestingBorder = Color.continuumOnSurface.opacity(0.09)

    /// Anchored dropdown panel fill
    static let continuumGlassStrong = Color(hex: "#1C222C").opacity(0.92)

    /// Shelf/base dropdown fill
    static let continuumGlassRegular = Color(hex: "#141820").opacity(0.72)

    /// Page scrim behind anchored dropdowns
    static let continuumDropdownScrim = Color(hex: "#141820").opacity(0.72)

    // MARK: - Request status dots

    /// Pending — amber.
    static let requestAmber = Color(hex: "#F59E0B")

    /// Approved / queued / downloading — sky.
    static let requestSky = Color(hex: "#38BDF8")

    /// Completed / in library — emerald.
    static let requestEmerald = Color(hex: "#34D399")

    /// Declined / failed — rose.
    static let requestRose = Color(hex: "#FB7185")

    // MARK: - Semantic Aliases

    /// Outline/border color
    static let continuumOutline = Color.continuumOnSurface.opacity(0.12)

    /// Overlay for sheets and modals
    static let continuumOverlay = Color(hex: "#141820").opacity(0.72)

    /// Divider/separator line color
    static let continuumDivider = Color.continuumOnSurface.opacity(0.12)

    /// Disabled control tint
    static let continuumDisabled = Color(hex: "#4B5563")
}
