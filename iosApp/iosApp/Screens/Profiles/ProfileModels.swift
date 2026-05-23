import Foundation

// MARK: - Profile Models

/// Minimal user profile as returned by the server. Carries the
/// playback-pref fields the player resolver consults at session start
/// (subtitle language, behavior, forced-subs toggle).
struct UserProfile: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let avatarEmoji: String?
    let hasPin: Bool
    let isChild: Bool
    let isPrimary: Bool
    let subtitleLanguage: String?
    let subtitleMode: String?
    let showForcedSubtitles: Bool?

    init(
        id: String,
        name: String,
        avatarEmoji: String?,
        hasPin: Bool,
        isChild: Bool,
        isPrimary: Bool = false,
        subtitleLanguage: String? = nil,
        subtitleMode: String? = nil,
        showForcedSubtitles: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarEmoji = avatarEmoji
        self.hasPin = hasPin
        self.isChild = isChild
        self.isPrimary = isPrimary
        self.subtitleLanguage = subtitleLanguage
        self.subtitleMode = subtitleMode
        self.showForcedSubtitles = showForcedSubtitles
    }
}

/// Request body for selecting a profile.
struct SelectProfileBody: Codable {
    let pin: String?
}

/// Request body for creating a new profile.
struct CreateProfileBody: Codable {
    let name: String
    let avatarEmoji: String?
    let pin: String?
    let isChild: Bool
}
