import SwiftUI

/// One outside service: its name (or approved logo), what Prairie uses it for,
/// and any notice its terms require. Passive text on every platform.
struct ThirdPartyCreditRow: View {
    let credit: ThirdPartyCredits.Credit
    var nameFont: Font = .headline
    var detailFont: Font = .subheadline
    var logoHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let logo = credit.logoAsset {
                // The logo replaces the name. TMDB's terms ask for it to stay
                // less prominent than Prairie's own branding.
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: logoHeight)
                    .padding(.vertical, 2)
            } else {
                Text(credit.name)
                    .font(nameFont)
                    .foregroundStyle(Color.prairieOnSurface)
            }
            Text(credit.use)
            if let notice = credit.notice {
                Text(notice)
            }
        }
        .font(detailFont)
        .foregroundStyle(Color.prairieSecondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([credit.name, credit.use, credit.notice].compactMap { $0 }.joined(separator: ". "))
    }
}

#if !os(tvOS)
/// Settings > About > Acknowledgements: the outside services whose data or
/// artwork Prairie shows, then the open source licenses.
struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                ForEach(ThirdPartyCredits.credits) { credit in
                    ThirdPartyCreditRow(credit: credit)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.prairieGroupedCell)
                }
            } header: {
                Text("Services")
                    .foregroundStyle(Color.prairieSecondaryText)
            } footer: {
                Text(ThirdPartyCredits.trademarkNotice)
                    .foregroundStyle(Color.prairieSecondaryText)
            }

            Section {
                NavigationLink {
                    OpenSourceAcknowledgementsView()
                } label: {
                    Text("Open Source Licenses")
                        .foregroundStyle(Color.prairieOnSurface)
                }
                .listRowBackground(Color.prairieGroupedCell)
            } header: {
                Text("Open Source")
                    .foregroundStyle(Color.prairieSecondaryText)
            } footer: {
                Text("Prairie's license, and the licenses and exact source revisions of the code built into it.")
                    .foregroundStyle(Color.prairieSecondaryText)
            }
        }
        .settingsListChrome()
        .navigationTitle("Acknowledgements")
        .prairieNavigationTitleDisplayMode(.inline)
        .prairieToolbarColorSchemeDark()
    }
}
#endif
