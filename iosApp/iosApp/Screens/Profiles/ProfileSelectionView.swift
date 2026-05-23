import SwiftUI

/// "Who's watching?" profile picker. Cinematic household layout: the tint
/// of each tile carries the profile's identity, focus lifts the tile with
/// a colored halo, and a soft radial gradient grounds the row so the black
/// background doesn't feel like dead space.
struct ProfileSelectionView: View {
    var router: AppRouter
    @State private var viewModel = ProfileSelectionViewModel()
    @State private var showPINEntry: Bool = false
    @State private var selectedProfile: UserProfile?
    @State private var showCreateProfile: Bool = false
    @State private var pinEntryPurpose: PINEntryPurpose = .profileSelection

    private enum PINEntryPurpose {
        case profileSelection
        case profileManagement
    }

    var body: some View {
        ZStack {
            background

            pickerContent
                #if os(tvOS)
                .disabled(showPINEntry)
                .accessibilityHidden(showPINEntry)
                #endif
        }
        .task {
            await viewModel.loadProfiles()
        }
        #if os(tvOS)
        .overlay {
            pinEntryOverlay
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $showCreateProfile, onDismiss: handleCreateProfileDismissed) {
            CreateProfileView {
                showCreateProfile = false
                Task { await viewModel.loadProfiles() }
            }
        }
        #else
        .sheet(isPresented: $showCreateProfile, onDismiss: handleCreateProfileDismissed) {
            CreateProfileView {
                showCreateProfile = false
                Task { await viewModel.loadProfiles() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        #endif
        #if !os(tvOS)
        .sheet(isPresented: $showPINEntry) {
            pinEntryContent
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    // MARK: - Background

    /// Pure black canvas with a soft radial spotlight behind the row. The
    /// radial is 8% white at the center fading to transparent, so the
    /// tiles have somewhere to "sit" without the background reading as a
    /// gradient card.
    private var background: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.07), Color.black.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: 900
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var pickerContent: some View {
        if viewModel.isLoading && viewModel.profiles.isEmpty {
            LoadingView(message: "Loading profiles...")
        } else if let error = viewModel.error, viewModel.profiles.isEmpty {
            ErrorView(state: error, onRetry: { Task { await viewModel.loadProfiles() } })
        } else {
            content
        }
    }

    private var content: some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            tileRow
                .padding(.horizontal, 80)

            Spacer(minLength: 0)
        }
        #else
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Spacer()
                changeServerChip
                signOutChip
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 36) {
                    header
                    tileRow
                        .padding(.horizontal, horizontalPadding)
                }
                .padding(.top, headerTopPadding)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        #endif
    }

    private var header: some View {
        #if os(tvOS)
        HStack(alignment: .top, spacing: 12) {
            Spacer(minLength: 0)
            titleBlock
                .frame(maxWidth: .infinity)
                .padding(.leading, 60) // visually balance the top-right chips
                .accessibilityAddTraits(.isHeader)

            changeServerChip
            signOutChip
        }
        .padding(.top, headerTopPadding)
        .padding(.horizontal, 60)
        // Without this, pressing Up from a centered profile tile can't
        // reach the Sign Out chip — the focus engine looks for a
        // focusable element roughly above the current one, and the chip
        // is pinned to the top-right corner. `focusSection` tells the
        // engine to treat the whole header row as a valid upward target.
        .focusSection()
        #else
        titleBlock
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
        #endif
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Who's watching?")
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("Select your profile")
                .font(.system(size: subtitleSize, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// Small ghost chip in the top-right. Signing out is utility, not a
    /// primary action — tucking it here frees the center of the screen
    /// for the identity moment.
    private var signOutChip: some View {
        Button {
            router.signOutAndReset()
        } label: {
            HStack(spacing: 6) {
                Text("Sign Out")
                    .font(.system(size: chipSize, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: chipSize - 1, weight: .medium))
            }
        }
        .buttonStyle(GhostChipButtonStyle())
    }

    /// Companion to `signOutChip`. Routes to the server picker so the
    /// user can switch between saved servers (or add a new one) without
    /// first signing out.
    private var changeServerChip: some View {
        Button {
            router.navigate(to: .serverList)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: chipSize - 1, weight: .medium))
                Text("Change Server")
                    .font(.system(size: chipSize, weight: .medium))
            }
        }
        .buttonStyle(GhostChipButtonStyle())
    }

    private var tileRow: some View {
        let grid = LazyVGrid(
            columns: [GridItem(.adaptive(minimum: tileMinWidth, maximum: tileMaxWidth), spacing: tileSpacing)],
            spacing: rowSpacing
        ) {
            ForEach(viewModel.profiles) { profile in
                ProfileTile(profile: profile) {
                    handleProfileTap(profile)
                }
            }
            AddProfileTile { handleAddProfileTap() }
        }

        #if os(tvOS)
        // Mirror of the header's `focusSection()`. Without this, pressing
        // Down from the Sign Out chip (top-right) has no section to
        // descend into — the focus engine's spatial search can't find
        // the centered tile grid from a corner anchor and focus gets
        // stuck on Sign Out. Making the grid a focus section gives the
        // engine a guaranteed target below the header.
        return grid.focusSection()
        #else
        return grid
        #endif
    }

    private func handleProfileTap(_ profile: UserProfile) {
        pinEntryPurpose = .profileSelection
        if profile.hasPin {
            selectedProfile = profile
            showPINEntry = true
        } else {
            Task { await viewModel.selectProfile(profile, router: router) }
        }
    }

    private func handleAddProfileTap() {
        guard let primaryProfile = viewModel.primaryProfile else {
            viewModel.error = ErrorState(
                statusCode: nil,
                message: "Couldn't find the primary profile needed to create another profile."
            )
            return
        }

        if primaryProfile.hasPin {
            pinEntryPurpose = .profileManagement
            selectedProfile = primaryProfile
            showPINEntry = true
            return
        }

        Task {
            do {
                try await viewModel.prepareForProfileManagement()
                await MainActor.run { showCreateProfile = true }
            } catch {
                await MainActor.run {
                    viewModel.error = ErrorState(error)
                }
            }
        }
    }

    private func handleCreateProfileDismissed() {
        Task { await viewModel.clearTemporaryManagementContextIfNeeded() }
    }

    @ViewBuilder
    private var pinEntryOverlay: some View {
        if showPINEntry {
            pinEntryContent
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
        }
    }

    @ViewBuilder
    private var pinEntryContent: some View {
        if let profile = selectedProfile {
            PINEntryView(
                profile: profile,
                onCancel: { showPINEntry = false }
            ) { pin in
                handlePINEntry(profile: profile, pin: pin)
            }
        }
    }

    private func handlePINEntry(profile: UserProfile, pin: String) {
        Task {
            do {
                switch pinEntryPurpose {
                case .profileSelection:
                    try await viewModel.selectProfileWithPIN(profile, pin: pin, router: router)
                case .profileManagement:
                    try await viewModel.prepareForProfileManagement(pin: pin)
                    await MainActor.run { showCreateProfile = true }
                }
            } catch {
                await MainActor.run {
                    viewModel.error = ErrorState(error)
                }
            }
        }
        showPINEntry = false
    }

    // MARK: - Platform sizing

    #if os(tvOS)
    private let titleSize: CGFloat = 64
    private let subtitleSize: CGFloat = 22
    private let chipSize: CGFloat = 18
    private let headerTopPadding: CGFloat = 100
    private let tileMinWidth: CGFloat = 300
    private let tileMaxWidth: CGFloat = 340
    private let tileSpacing: CGFloat = 56
    private let rowSpacing: CGFloat = 72
    #else
    private let titleSize: CGFloat = 32
    private let subtitleSize: CGFloat = 15
    private let chipSize: CGFloat = 13
    private let headerTopPadding: CGFloat = 24
    private let tileMinWidth: CGFloat = 140
    private let tileMaxWidth: CGFloat = 180
    private let tileSpacing: CGFloat = 16
    private let rowSpacing: CGFloat = 28
    private let horizontalPadding: CGFloat = 20
    #endif
}

// MARK: - Ghost chip button style

/// Translucent pill with a focus-aware outline. Used for utility actions
/// (Sign Out / Cancel) so they read as "secondary" next to the identity
/// tiles and primary buttons.
private struct GhostChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostChipBody(configuration: configuration)
    }
}

private struct GhostChipBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.continuumBackground : Color.white.opacity(0.75))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    isFocused ? Color.white : Color.white.opacity(0.08)
                )
            )
            .overlay(
                Capsule().stroke(
                    isFocused ? Color.clear : Color.white.opacity(0.22),
                    lineWidth: 1
                )
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            #if os(tvOS)
            .focusEffectDisabled()
            #endif
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
    }
}
