import SwiftUI

struct SearchMediaTypeMenu: View {
    @Binding var selectedMediaType: SearchMediaType

    var body: some View {
        Menu {
            ForEach(SearchMediaType.allCases) { mediaType in
                Button {
                    selectedMediaType = mediaType
                } label: {
                    if selectedMediaType == mediaType {
                        Label(mediaType.title, systemImage: "checkmark")
                    } else {
                        Text(mediaType.title)
                    }
                }
                .accessibilityAddTraits(selectedMediaType == mediaType ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedMediaType.title)
                    .font(.continuumBody)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .bold()
                    .imageScale(.small)
            }
            .foregroundStyle(Color.continuumOnSurface)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(Color.continuumChromeRestingFill)
            )
            .overlay(
                Capsule().strokeBorder(Color.continuumChromeRestingBorder, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Media type")
        .accessibilityValue(selectedMediaType.title)
    }
}
