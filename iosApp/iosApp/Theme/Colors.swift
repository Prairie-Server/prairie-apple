import SwiftUI

extension Color {
    // MARK: - Core Palette (Prairie Dusk)
    //
    // Mirrors prairie-server Phase 3 / prairie-smarttv tokens:
    // deep slate surfaces + amber wheat accent (#e0a84a).

    /// Deep slate background (#141820)
    static let prairieBackground = Color(hex: "#141820")

    /// Elevated surface (#1c222c)
    static let prairieSurface = Color(hex: "#1C222C")

    /// Surface variant for containers (#0e1116 sidebar tone)
    static let prairieSurfaceVariant = Color(hex: "#0E1116")

    /// Surface for elevated containers (#222B38)
    static let prairieSurfaceElevated = Color(hex: "#222B38")

    /// Primary interactive / brand accent — amber wheat
    static let prairiePrimary = Color(hex: "#E0A84A")

    /// Kept for backwards compat — same as primary
    static let prairiePrimaryLight = Color(hex: "#E0A84A")

    /// Primary text color (#F2EEE6)
    static let prairieOnSurface = Color(hex: "#F2EEE6")

    /// Accent for enabled control states (toggles, prominent buttons).
    static let prairieAccent = Color(hex: "#E0A84A")

    /// Brand accent for wordmark / first-run moments (same amber as dusk primary).
    static let prairieBrandOrange = Color(hex: "#E0A84A")

    /// Muted/secondary text (#9AA3B2)
    static let prairieSecondaryText = Color(hex: "#9AA3B2")

    /// Track of an on switch. Prairie keeps its amber accent on switches
    /// (upstream uses the system green because its palette is monochrome).
    static let prairieSwitchOn = Color.prairieAccent

    /// Row background of an inset-grouped list, shared by Settings and
    /// Downloads — Prairie's elevated slate surface.
    static let prairieGroupedCell = Color(hex: "#1C222C")

    /// Fill behind Settings row icons.
    static let prairieIconTile = Color(hex: "#222B38")

    /// Storage-breakdown series color (Prairie sky).
    static let prairieBrandBlue = Color(hex: "#38BDF8")

    /// Storage-breakdown movies color (Prairie rose).
    static let prairieBrandRed = Color(hex: "#FB7185")

    /// Error red (#B00020)
    static let prairieError = Color(hex: "#B00020")

    /// Success green
    static let prairieSuccess = Color.green

    /// Warning amber (ratings stars)
    static let prairieWarning = Color(hex: "#FFC107")

    // MARK: - Skyline chrome (guide §4)

    /// Selected-but-unfocused tab/pill capsule fill — warm ink @ 14%
    static let prairieChromeSelectedFill = Color.prairieOnSurface.opacity(0.14)

    /// Inner border of the selected capsule
    static let prairieChromeSelectedBorder = Color.prairieOnSurface.opacity(0.10)

    /// Resting pill/chip fill
    static let prairieChromeRestingFill = Color.prairieOnSurface.opacity(0.07)

    /// Hairline border on resting pills/chips
    static let prairieChromeRestingBorder = Color.prairieOnSurface.opacity(0.09)

    /// Anchored dropdown panel fill
    static let prairieGlassStrong = Color(hex: "#1C222C").opacity(0.92)

    /// Shelf/base dropdown fill
    static let prairieGlassRegular = Color(hex: "#141820").opacity(0.72)

    /// Page scrim behind anchored dropdowns
    static let prairieDropdownScrim = Color(hex: "#141820").opacity(0.72)

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
    static let prairieOutline = Color.prairieOnSurface.opacity(0.12)

    /// Overlay for sheets and modals
    static let prairieOverlay = Color(hex: "#141820").opacity(0.72)

    /// Divider/separator line color
    static let prairieDivider = Color.prairieOnSurface.opacity(0.12)

    /// Disabled control tint
    static let prairieDisabled = Color(hex: "#4B5563")
}
