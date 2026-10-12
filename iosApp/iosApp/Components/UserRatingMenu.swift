import SwiftUI

/// Labels and choices for the title detail rating control: 1–5 stars plus
/// "Clear Rating".
enum UserRatingChoice {
    static func caption(_ rating: Int?) -> String {
        rating.map { "\($0) Star" + ($0 == 1 ? "" : "s") } ?? "Rate"
    }

    static func icon(_ rating: Int?) -> String {
        rating == nil ? "star" : "star.fill"
    }

    static func accessibilityLabel(_ rating: Int?) -> String {
        rating.map { "Your rating: \(caption($0))" } ?? "Rate this title"
    }

    /// Filled up to and including the current rating.
    static func icon(for stars: Int, current rating: Int?) -> String {
        stars <= (rating ?? 0) ? "star.fill" : "star"
    }
}

#if os(tvOS)
extension UserRatingChoice {
    private static let clearID = "clear"

    static func popoverItems(_ rating: Int?) -> [TVActionPopoverItem] {
        var items = (1...5).map { stars in
            TVActionPopoverItem(id: String(stars), title: caption(stars),
                                systemImage: icon(for: stars, current: rating), isSelected: stars == rating)
        }
        if rating != nil {
            items.append(TVActionPopoverItem(id: clearID, title: "Clear Rating", systemImage: "star.slash"))
        }
        return items
    }

    /// The rating an item sets; nil for "Clear Rating".
    static func rating(for item: TVActionPopoverItem) -> Int? { Int(item.id) }
}
#else
/// Menu content for the phone/Mac rating action.
struct UserRatingMenuItems: View {
    let rating: Int?
    let onSet: (Int?) -> Void

    var body: some View {
        ForEach(1...5, id: \.self) { stars in
            Button { onSet(stars) } label: {
                Label(UserRatingChoice.caption(stars),
                      systemImage: UserRatingChoice.icon(for: stars, current: rating))
            }
        }
        if rating != nil {
            Button(role: .destructive) { onSet(nil) } label: {
                Label("Clear Rating", systemImage: "star.slash")
            }
        }
    }
}
#endif
