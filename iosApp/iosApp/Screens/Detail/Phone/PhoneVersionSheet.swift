#if !os(tvOS)
import SwiftUI

/// Version chooser presented as a `.sheet`. Mirrors the tvOS
/// `TVVersionPillButton` menu — Auto + every available file, with a
/// trailing checkmark on the active selection — but laid out as a
/// modal list that fits a phone tap target.
struct PhoneVersionSheet: View {
    let title: String
    let versions: [PhoneVersionRow]
    let selectedFileId: Int?
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        mobileBody
        #endif
    }

    #if os(macOS)
    private var macOSBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.continuumOnSurface)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .modifier(VersionGlassCard(isSelected: false, isInteractive: true, cornerRadius: 999))
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    autoRow

                    ForEach(versions) { row in
                        versionButton(row: row)
                    }
                }
                .padding(.vertical, 2)
            }

        }
        .padding(22)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 320, idealHeight: 400)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.continuumSurfaceElevated.opacity(0.28))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
    #endif

    #if !os(macOS)
    private var mobileBody: some View {
        NavigationStack {
            List {
                Section {
                    autoRow
                }
                Section {
                    ForEach(versions) { row in
                        versionButton(row: row)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Color.continuumBackground.ignoresSafeArea())
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem {
                    Button("Done") { dismiss() }
                        .tint(.continuumOnSurface)
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(.continuumOnSurface)
                }
                #endif
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    #endif

    private var autoRow: some View {
        Button {
            onSelect(nil)
            dismiss()
        } label: {
            VersionOptionLabel(
                title: "Auto",
                detail: "Best match for this device",
                isSelected: selectedFileId == nil
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .modifier(VersionGlassCard(isSelected: selectedFileId == nil, isInteractive: true))
        #else
        .listRowBackground(Color.continuumSurfaceVariant)
        #endif
    }

    @ViewBuilder
    private func versionButton(row: PhoneVersionRow) -> some View {
        Button {
            onSelect(row.fileId)
            dismiss()
        } label: {
            VersionOptionLabel(
                title: row.title,
                detail: row.detail,
                isSelected: selectedFileId == row.fileId
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .modifier(VersionGlassCard(
            isSelected: selectedFileId == row.fileId,
            isInteractive: true
        ))
        #else
        .listRowBackground(Color.continuumSurfaceVariant)
        #endif
    }
}

/// Plain-data row passed into `PhoneVersionSheet`. Decoupling the data
/// from `FileVersion` lets us reuse the sheet for the season detail's
/// next-up `EpisodeFile` picker.
struct PhoneVersionRow: Identifiable, Hashable {
    let fileId: Int
    let title: String
    let detail: String?
    var id: Int { fileId }
}

private struct VersionOptionLabel: View {
    let title: String
    let detail: String?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.continuumOnSurface)
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.continuumOnSurface)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#if os(macOS)
private struct VersionGlassCard: ViewModifier {
    let isSelected: Bool
    let isInteractive: Bool
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = isSelected ? Color.white.opacity(0.18) : Color.clear

        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                if #available(iOS 26, macOS 26, *) {
                    shape
                        .fill(Color.clear)
                        .glassEffect(
                            isInteractive
                                ? Glass.regular.tint(tint).interactive()
                                : Glass.regular.tint(tint),
                            in: .rect(cornerRadius: cornerRadius)
                        )
                } else {
                    shape
                        .fill(Color.continuumSurfaceElevated.opacity(isSelected ? 0.34 : 0.22))
                        .background(.ultraThinMaterial, in: shape)
                }
            }
            .overlay {
                shape.stroke(Color.white.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
            }
    }
}
#endif
#endif
