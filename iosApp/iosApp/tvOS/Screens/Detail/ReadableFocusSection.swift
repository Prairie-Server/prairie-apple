#if os(tvOS)
import SwiftUI

/// Makes an otherwise non-interactive block of static text (the detail
/// page's "Info" facts grid and "About" tagline/overview) a *readable*
/// focus stop on tvOS.
///
/// Why this exists: the Info/About sections used to be plain
/// `.focusable().focusEffectDisabled()` blocks. That made them invisible
/// dead stops — focus landed on them with no visible cue, so the page
/// looked frozen. They were de-focusabled to fix that, but then d-pad
/// Down skipped them entirely (cast rail → Recommended rail), so the
/// scroll never paused to let the user read the facts or overview.
///
/// This modifier restores them as focus stops *with* a visible, restrained
/// cue: focusing the block fades in a faint rounded surface fill + hairline
/// border (the same idiom as the rest of the mono theme), and because the
/// block is inside the detail `ScrollView`, gaining focus scrolls it into
/// view so the user can read it.
///
/// Focus mechanics — deliberate choices:
///   * Plain `.focusable()` only. NO `prefersDefaultFocus` and NO
///     `.defaultFocus(...)`. The hero's primary Play button owns initial
///     focus via `prefersDefaultFocus(true, in: detailFocusNamespace)`;
///     a bare focusable carries `.automatic` priority and no preference
///     flag, so it can never win the scope's initial focus evaluation.
///     Play stays the landing target on appear.
///   * NO `.focusSection()`. A focus section groups *multiple* focusable
///     children so the d-pad treats them as one region; these blocks are a
///     single focusable leaf, so a focus section would be degenerate and
///     could swallow directional moves. Vertical travel between sibling
///     blocks in the body `VStack` already works through the scope.
///   * `.focusEffectDisabled()` suppresses tvOS's default white halo so the
///     only cue is our subtle fill/border — matching how the pill and card
///     styles own their own focus appearance elsewhere.
private struct ReadableFocusSection: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            // Inset so the focus surface can bleed slightly past the text
            // without nudging the layout when unfocused.
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: ContinuumTheme.cardCornerRadius, style: .continuous)
                    .fill(Color.continuumSurfaceElevated.opacity(isFocused ? 0.6 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: ContinuumTheme.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(isFocused ? 0.18 : 0), lineWidth: 1)
                    )
            )
            // Counteract the inset so adding the modifier doesn't shift the
            // section's content origin relative to its neighbours.
            .padding(.horizontal, -28)
            .padding(.vertical, -24)
            .contentShape(RoundedRectangle(cornerRadius: ContinuumTheme.cardCornerRadius, style: .continuous))
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
    }
}

extension View {
    /// Make a static-text detail section (Info / About) a visible, readable
    /// focus stop. See `ReadableFocusSection` for the focus-priority
    /// rationale (it never steals initial focus from the hero's Play
    /// button, and intentionally omits `.focusSection()`).
    func readableFocusSection() -> some View {
        modifier(ReadableFocusSection())
    }
}
#endif
