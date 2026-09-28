#if os(iOS)
import SwiftUI

struct SettingsAccountCard: View {
    let avatar: String?
    /// Server-resolved avatar image URL (`avatar_url`), preferred over the
    /// raw `avatar` ref when present.
    var avatarImageUrl: String? = nil
    let name: String
    let subtitle: String
    let isAdministrator: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ProfileAvatarView(avatar: avatar, imageUrl: avatarImageUrl, name: name, size: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Current profile")
                        .font(.caption)
                        .foregroundStyle(Color.prairieSecondaryText)

                    Text(name)
                        .font(.headline)
                        .foregroundStyle(Color.prairieOnSurface)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.prairieSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isAdministrator {
                    Text("Admin")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(Color.prairieAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.prairieAccent.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(Color.prairieSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.prairieSurfaceElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.prairieOutline, lineWidth: 1)
        }
        .accessibilityHint("Switches to a different profile")
    }
}
#endif
