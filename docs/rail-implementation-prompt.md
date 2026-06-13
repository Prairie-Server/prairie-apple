# Implementation prompt — Rail Phase 1 (tvOS)

Copy everything below the line into a fresh Claude Code session at the root of
`silo-apple`. Run phases as separate sessions: finish and merge Phase 1 before
prompting Phase 2 (library header tabs replacing the mode slider) and Phase 3
(badges, first-run hint, motion pass, Android Calendar parity). An Android
adaptation note is at the end.

**Branching:** create `feature/rail-phase-1` **from `main`**, not from any
Skyline branch. Rail and Skyline rebuild the same chrome (`TVMainTabView`,
`TVTopMenuBar`) in incompatible ways — they are parallel prototypes to compare,
not stacked work. If Skyline work has already been merged to `main`, say so in
your first status update and adapt to the merged state instead of `main`'s
older layout.

---

Implement **Phase 1 of the Rail navigation redesign** for the tvOS app.

## Read these first, in order

1. `docs/rail-design-guide.md` — the spec for this work. Source of truth for
   IA, tokens, components, the focus model (§7 especially), and the tvOS file
   mapping (§10). Where this prompt and the guide conflict, the guide wins.
   It builds on `docs/skyline-design-guide.md` §2/§4/§5 for shared tokens and
   card/row specs — skim those sections too.
2. The Rail mockups: `docs/tvos-redesign-mockups/shots/b1*.png`, `b2*.png`,
   `b3*.png` (b3's header tabs are Phase 2 — visual reference only for now).
3. The current navigation layer before changing it:
   `iosApp/iosApp/tvOS/Navigation/TVMainTabView.swift`,
   `iosApp/iosApp/tvOS/Navigation/TVTopMenuBar.swift`,
   `iosApp/iosApp/tvOS/Screens/Libraries/TVLibrariesTabView.swift`,
   `iosApp/iosApp/Theme/ContinuumTheme.swift`.

## Phase 1 scope (and nothing more)

1. **Build `TVRail`** (new, under `iosApp/iosApp/tvOS/Navigation/`): the
   104 px collapsed strip + 480 px expanded glass panel per guide §5.1–§5.2
   and §4 tokens. Strip is display-only; the panel is the interactive surface.
   Expansion is driven purely by focus entering the rail zone; collapse on
   exit. Panel overlays content (no reflow) over the `scrim.railOpen` dim.
2. **Replace the top menu.** Root chrome becomes the rail with rows:
   profile block · Search · Home · Calendar · LIBRARIES (one row per visible
   library, server order, with counts) · MY STUFF (Watchlist / Favorites /
   History) · Settings (pinned bottom). Delete `TVTopMenuBar` usage from root
   screens; fold its profile-dropdown actions into the panel (profile block →
   existing profile switcher; admin entry moves to Settings if it was only in
   the dropdown).
3. **Delete the Libraries tab machinery:** the Libraries root, the
   full-screen picker (`TVLibraryActionsModal` / `TVLibraryActionsPanel`).
   Selecting a library row opens that library's existing landing page
   unchanged (the mode slider stays for Phase 1 — do not build header tabs
   yet; leave a `// Rail Phase 2: header tabs` marker).
4. **Fold For You into Home:** remove the For You root; append the
   recommendation rows after Continue Watching reusing the existing data
   source and `SectionRow`.
5. **Content inset:** root screens move their leading content edge to
   `rail.contentInset` (176) per guide §5.4; hero/rows otherwise unchanged.

Out of scope: library header tabs/chips/Genres (Phase 2), counts badges and
first-run hints (Phase 3), any Android or server work, any iOS/macOS behavior
changes.

## Repo constraints

- After any target/file-layout change: `cd iosApp && xcodegen generate`. Never
  hand-edit `Silo.xcodeproj`. Never touch signing.
- New files under `iosApp/iosApp/tvOS/`; shared screens (Home, Search,
  Calendar, Recommendations) also compile for iOS/macOS — guard tvOS-only
  changes and keep the other platforms building unchanged.
- Match existing style: `TV` prefix, tokens from `ContinuumTheme` /
  `Colors.swift` (add the guide §4 rail tokens to the theme; no hardcoded
  values). No new dependencies. No tests for this UI work unless shared logic
  changes (per `CLAUDE.md`).
- Commit in reviewable increments (rail component → root rewiring → libraries
  flat rows → for-you fold), not one mega-commit.

## Focus & navigation requirements (treat as acceptance criteria)

These encode hard-won tvOS lessons from this codebase — the current app uses a
custom TOP menu precisely because a system left sidebar steals leftward focus.
Rail reintroduces a left edge, so guide §7.3's guards are non-negotiable:

- **Never use `TabView(.sidebarAdaptable)` or any system sidebar.** The rail
  is a custom `focusSection()`; a left-move from a row interior must stay in
  the row — only a leftmost-item left-move crosses into the rail.
- **Lossless expansion.** When the rail gains focus, record exactly which
  content element had focus; right or Menu from the rail collapses and
  restores that element. Verify the round-trip from a mid-row position, a
  grid, and the hero.
- **No reflow.** The panel overlays; content never moves on expand/collapse.
- **Collapsed strip is never focusable.** All interaction happens in the
  expanded panel; focus entering the zone and the expand animation are the
  same event (220 ms per guide §4.2). Panel entry focus = current root's row.
- **Press-to-commit.** Focusing rail rows never navigates; press selects, then
  collapse and move focus to the new page's entry target (Home → hero primary
  action; library → first content item; Calendar → today's shelf).
- **Keep the single shared `NavigationStack`** + `navigationDestination(for:
  Route.self)`. Rail row selection swaps root content; it is not a push. No
  nested stacks, no `NavigationLink(destination:)`, one registration per type.
- **Back/Menu chain** via `onExitCommand` at the content zone: content → rail
  (expanded, focus on current row) → non-Home → select Home → Home → system.
  Never trap, including while the panel is open.
- **Stable identity around focus:** never rebuild the focused view in the same
  transaction that moves focus; destination switches crossfade 200 ms and
  re-target focus in a follow-up task. Custom chrome keeps
  `.focusEffectDisabled()` + focus-driven visuals (existing pattern).
- **Settings pickers stay `sheet(item:)`** (tvOS NavigationStack pushes from
  that context are unreliable — see comments in `TVSettingsView.swift`).
- **Accessibility:** panel rows expose VoiceOver labels ("Movies, 4 of 9",
  current root reads as selected); Reduce Motion snaps the panel (no
  slide/scale) and disables hero auto-advance.

## Verification before you call it done

1. `cd iosApp && xcodegen generate`
2. Build all three:
   - `xcodebuild build -project Silo.xcodeproj -scheme SiloTV -destination 'platform=tvOS Simulator,name=Apple TV' CODE_SIGNING_ALLOWED=NO`
   - same for scheme `Silo` (iPhone 17 Pro sim) and `SiloMac` (`platform=macOS`)
3. Run the tvOS simulator and walk the focus map:
   - cold start → Home, focus on hero primary action, rail collapsed with Home
     indicator
   - scroll mid-row in Continue Watching, press left repeatedly: focus walks
     to the row's first item, ONE more left opens the rail; immediate right
     returns to that exact first item
   - rail: down to a library row, press → library landing, rail collapsed
     with that library's indicator lit, focus on first content item
   - My Stuff rows route to Watchlist/Favorites/History; Settings row works
   - Menu from content → rail open; Menu again (non-Home) → Home; Menu on
     Home → app exits to system
   - simulator's touch-surface swipe (continuous input) inside a row does not
     open the rail
4. Confirm no dead references to the removed Libraries/For You roots and that
   Top Shelf / `continuum://` deep links still resolve.
5. Report results honestly, including anything you could not verify in the
   simulator (e.g., real-remote swipe feel — flag it for a device pass with
   the `tvos-deploy-and-log` skill, ask before using it).

---

## Adapting this prompt for `silo-android` (androidTvApp)

Swap the read-first list for `TvAppNavigation.kt`, `TvMainShell.kt`,
`TvTopMenuBar.kt`, `TvLibrariesScreen.kt`, theme files in `ui/theme/`; use the
Android column of guide §10. Constraints: Compose + `androidx.tv.material3`
only; prefer a custom strip+panel — use `NavigationDrawer` from tv.material3
only if it satisfies guide §7.3's guards under d-pad testing. dp = guide px ÷ 2
(strip 52 dp, panel 240 dp, inset 88 dp), keep the 0.86 font scale, use
`focusRequester` + `focusProperties` + `focusRestorer` for the zone bridging
and lossless-expansion invariant, `BackHandler` for the Menu chain, and
`./gradlew :androidTvApp:assembleDebug` to verify. Phase 1 scope is identical;
Calendar is a rail row only if the screen exists — otherwise omit the row until
the parity phase ships it.
