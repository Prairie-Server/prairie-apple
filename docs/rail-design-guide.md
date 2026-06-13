# Rail Design Guide

**Silo TV client navigation redesign — tvOS & Android TV (alternative direction)**

Status: documented for implementation/prototyping. Skyline
(`docs/skyline-design-guide.md`) was the original consensus pick; Rail is its
sibling spec sharing the same brand DNA, tokens-by-reference, and several
identical decisions (For You folds into Home, modal picker and mode slider are
deleted, chrome exists only on root screens).
Mockups: `docs/tvos-redesign-mockups/` (`b1`–`b3` + rendered PNGs in `shots/`)
Scope: 10-foot clients only (tvOS + Android TV).

---

## 1. What Rail is

Rail moves all navigation to a **collapsible left edge**: a slim icon strip
that expands into a glass panel listing every destination — and **every
library individually, flat, with live counts**. Browsing chrome inside a
library moves into the content header as underlined text tabs.

| Today | Rail |
|---|---|
| "Libraries" tab → full-screen modal picker | Every library is a row in the rail: left, pick, done — ≤2 presses from anywhere |
| Recommended ↔ Collections mode slider | Underlined **content tabs** in the library header: `Recommended · Browse · Collections · Genres` |
| "For You" as separate tab | Folded into Home as rows (same as Skyline) |
| Watchlist/Favorites/History buried in Settings | First-class `MY STUFF` rows in the rail |

**Rail vs Skyline in one line:** Skyline merges libraries into type tabs and
needs a scope dropdown + merged queries; Rail lists libraries verbatim and
needs neither — its cost is that the left edge owns d-pad-left (§7.3).

### Principles

1. **One surface, zero modals.** Every destination lives in one place. Nothing
   navigational is ever a full-screen takeover.
2. **Libraries are first-class, not merged.** Power users with many libraries
   see exact names and counts; no virtual scopes, no server changes.
3. **Chrome yields to content.** Collapsed, the rail is 104 px of glyphs over
   an edge scrim; the frame belongs to the artwork.
4. **No hidden modes.** What the grid shows is selected by visible tabs and
   chips in the header, never a sticky corner toggle.
5. **Keep the brand DNA.** Same tokens, focus grammar, and motion as today
   (see Skyline guide §4 — all of it applies unless overridden here).

---

## 2. Units & scaling

Identical to Skyline guide §2: dimensions are mockup px at 1920×1080;
tvOS pt = px, Android dp = px ÷ 2, Android type keeps the 0.86 font scale.

---

## 3. Information architecture

```
RAIL (left edge, on all root screens)
├─ Profile block (avatar; expanded: name + server host)      → profile switcher
├─ Search
├─ Home
├─ Calendar
├─ ── LIBRARIES ──────────  (one row per visible library, server sortOrder)
│   Movies (1,284) · TV Shows (412) · Music (8,932) · Audiobooks (167) · …
├─ ── MY STUFF ───────────  (expanded panel only)
│   Watchlist · Favorites · History
└─ Settings (pinned bottom)

LIBRARY PAGE — header content tabs (replace the mode slider):
    Recommended (default) · Browse · Collections · Genres
    (Music: Overview · Artists · Albums · Playlists · Genres)
    (Audiobooks: Overview · Browse · Authors · Collections)
    + filter chips (Browse): Sort · Unwatched · Year …
    + A–Z rail on the right edge (Browse)

FULL-SCREEN (no rail): item detail · person · collection detail · player ·
    admin · auth flow
```

### 3.1 Rail content rules

- One row per **library**, never merged. Order = server `sortOrder`. Counts
  come from the libraries endpoint and may be stale by one refresh — display
  only, never blocking.
- `MY STUFF` rows appear in the expanded panel only; the collapsed strip shows
  primary glyphs (search/home/calendar/libraries/settings).
- More than ~9 library rows: the panel's middle region scrolls internally;
  profile block and Settings stay pinned. The collapsed strip clips with a
  fade — it is non-interactive (§5.1) so nothing is unreachable.
- Profile block press → existing profile switcher. `Switch Server` lives in
  Settings (Android) as today.

### 3.2 What is deleted

Same list as Skyline §3.2 (Libraries root, full-screen picker, mode slider,
For You root) **plus the persistent top menu bar itself** — the wordmark moves
into the expanded panel's profile block; the clock is not retained.

### 3.3 Where existing things go

| Existing | New home |
|---|---|
| Library landing "Recommended" mode | Library page → `Recommended` tab (default) |
| Library landing "Collections" mode | Library page → `Collections` tab |
| A–Z grid + alphabet rail | Library page → `Browse` tab (chips + A–Z rail) |
| For You rows | Home rows, after Continue Watching |
| Watchlist / Favorites / History | Rail `MY STUFF` (and stay in Settings) |
| Search | Rail row → existing search screen |
| Profile dropdown | Rail profile block + Settings |
| Calendar | Rail row; Android must build the screen for parity |

---

## 4. Design tokens

Everything in Skyline guide §4 applies (colors, radii, type ramp for shared
elements, motion idioms, "grain is mockup-only"). Rail-specific tokens:

| Token | Value | Notes |
|---|---|---|
| `rail.collapsedWidth` | 104 | icon strip |
| `rail.expandedWidth` | 480 | glass panel |
| `rail.contentInset` | 176 | content left edge (104 strip + 72 gutter) |
| `rail.edgeScrim` | 300 px gradient, black 78% → 0 | behind collapsed strip |
| `rail.panelSurface` | `#0A0A0C` @ 92% → `#0E0F12` @ 82%, blur 46, right hairline white 10% | expanded panel |
| `scrim.railOpen` | black @ 52% + blur 22 | content behind expanded panel |

### 4.1 Rail type additions

| Style | px | tvOS pt | Android sp | Weight / tracking |
|---|---|---|---|---|
| Panel row label | 22 | 22 | 11 | 600 |
| Panel row count | 16 | 16 | 8 | 500, tertiary |
| Panel section header | 13 mono | 13 | 7 (mono) | 600, +0.30 em, caps, tertiary |
| Profile name | 23 | 23 | 12 | 700 |
| Server host | 14 mono | 14 | 8 (mono) | 500, tertiary, +0.06 em |
| Library page title | 58 | 58 | 29 | 800, count suffix 22/500 tertiary |
| Header content tab | 22 | 22 | 11 | 600; selected 100% white, others 38% |
| Filter chip | 17 | 17 | 9 | 600 |
| Hero title (Home) | 104 | 104 | 52 | 800, +0.10 em, caps |

### 4.2 Rail motion

| Animation | Spec |
|---|---|
| Expand (focus enters rail) | 220 ms ease-out: panel slides/scales from the strip, labels fade in 80 ms after; `scrim.railOpen` fades 150 ms |
| Collapse (focus leaves rail) | 180 ms ease-in; content focus restored to the exact prior item |
| Row focus | invert-to-white, scale 1.02, 120 ms |
| Destination switch | 200 ms content crossfade (no slide) |
| Header tab switch | 200 ms crossfade + underline slides between tabs 180 ms |

Reduce Motion: panel snaps (no slide/scale), underline does not animate.

---

## 5. Components

### 5.1 Collapsed strip

- 104 wide, full height, over `rail.edgeScrim`. Top padding 52, bottom 48.
- Avatar 46 px circle at top (display of profile color/initial), then icon
  cells 56×56 (glyphs 26 px, radius 16) gap 10, hairline dividers inside 26 px
  gaps between groups, Settings glyph pinned bottom.
- Current root: icon at 100% white **plus** a 4×26 white bar 22 px left of the
  cell. All other icons 40% white.
- **The collapsed strip is never focusable.** It is a visual summary; the
  moment focus enters the rail zone the panel is already expanding. There is
  no interactive-but-collapsed state (this avoids invisible-focus bugs).

### 5.2 Expanded panel

- 480 wide overlay (content does **not** reflow), `rail.panelSurface`, shadow
  60/140 black 55%; padding 56 top / 28 right / 48 bottom / 40 left.
- Profile block: avatar 56 + name + host with 8 px green presence dot; press →
  profile switcher. 36 px gap below.
- Rows: icon 30 — label — count right-aligned; padding 13×16, radius 14,
  gap 18 between icon and label.
- Row states: resting = label @ 62%; **current root** = 100% white + 4×24
  white bar at the row's left inside edge; **focused** = inverted (white bg,
  black text, scale 1.02, count @ 55% black). Current ≠ focused — both
  grammars can show at once on different rows.
- Section headers per §4.1; My Stuff group; Settings row pinned via bottom
  alignment.

### 5.3 Library page header (replaces the mode slider)

- Title row at top 56: `TV Shows` 58/800 + `412 SERIES` count suffix.
- Tabs row 26 below, full-width hairline underneath: text tabs gap 44,
  selected = white + 3 px underline sitting on the hairline. Tabs commit on
  **press**; focus moves freely without changing content. Focused tab that is
  not selected shows the standard inverted capsule treatment around the label.
- Filter chips right-aligned in the same row (Browse tab only): capsule chips
  17/600, padding 8×18, white 7% bg + 10% border; value part white; active
  chip bg 16%. Chips open the existing option dialogs/sheets.
- Content area starts at 254. `Browse` shows the poster grid (6 columns,
  gap 26, 2:3) with the A–Z rail at the right edge (mono 15, current letter =
  inverted rounded chip, existing prefix-jump behavior).

### 5.4 Everything else

Hero (Home), cards, rows, badges, progress, skeletons: identical to Skyline
guide §5.4–§5.7 with Home hero title style per §4.1 above and content left
edge at `rail.contentInset` (176) instead of 88. The Continue-Watching thumb
is 348×196 at this inset (five fit).

---

## 6. Screens

### 6.1 Home (`b1`)

Collapsed strip · full-bleed hero (eyebrow `NEW EPISODE · TV SHOWS · TODAY`,
104 px title, meta badges, `Play Episode N` primary + `Go to Series`
secondary) · Continue Watching row · further rows (For You, Recently Added
per library) below the fold. Entry focus: hero primary action.

### 6.2 Rail expanded (`b2`)

Triggered purely by focus entering the rail zone (d-pad left from any leftmost
content item, or Menu per §7.2). Content dims under `scrim.railOpen`. Focus
lands on the **current root's row** (not the top row) so down/up radiate from
"you are here". Right or Menu collapses and restores prior content focus.

### 6.3 Library page (`b3`)

Header (§5.3) with `Recommended` selected by default; `Browse` = grid + chips
+ A–Z rail; `Collections` = existing collections grid; `Genres` = chip cloud →
filtered grid. Focus map: content ↔ header tabs ↔ rail. The A–Z rail is its
own focus column on the right edge: right from the last grid column enters it,
left returns to the grid.

### 6.4 Calendar / Search / Settings

Calendar and Search are unchanged screens reached from rail rows (Android
builds Calendar in the parity phase). Settings keeps its current screen;
remove its Library quick-links section once `MY STUFF` ships.

---

## 7. Focus & input model

### 7.1 Zones

Horizontal zones: **rail | content**. Within content, vertical zones as today
(hero → rows, or header tabs → grid). The rail is one `focusSection`
(tvOS) / one focus group with explicit `focusProperties` (Android).

### 7.2 Rules

- **Left from any leftmost content item** → rail (expands, focus on current
  root row). **Right from the rail** → collapse + restore the exact content
  item that had focus (store it when the rail opens; never re-derive it).
- Rows activate on **press**. Focusing rows never navigates.
- **Back/Menu chain:** content → rail (expanded) → if not on Home, select
  Home → system home. Implement at the content zone with `onExitCommand`
  (tvOS) / BackHandler (Android). A second Menu while the rail is open and
  Home is current exits the app — never trap.
- Dropdown-free design: the only overlay is the rail itself; it traps focus
  while open by construction (content is behind the scrim and not focusable).
- Entry targets: Home → hero primary; library page → first content item of
  the selected tab; Calendar → today's shelf (existing behavior).

### 7.3 The left-edge risk, and the required mitigations

A left rail is the pattern the current app's custom top bar was built to
avoid: the system sidebar (`TabView(.sidebarAdaptable)`) greedily claims
**every** leftward move. Rail is only acceptable as a **custom** component
with these guards — all four are requirements, not suggestions:

1. **Never use the system sidebar/TabView.** Custom strip + panel only, so
   left-moves inside a horizontally scrolled row stay in the row; only a
   leftmost-item left-move crosses the section boundary.
2. **Expansion must be lossless.** Open + immediate right must land focus
   exactly where it was. If that invariant holds, accidental expansion costs
   one press and zero context — annoying, not destructive.
3. **No layout shift.** The panel overlays; content never reflows, so an
   accidental open/close cannot cause scroll or focus drift.
4. **Swipe tolerance (Siri Remote):** the rail zone must not capture diagonal
   touchpad swipes from row interiors — verify with continuous-swipe input,
   not just discrete d-pad presses, before sign-off.

---

## 8. State & persistence rules

| State | Persistence |
|---|---|
| Current root (rail row) | Session only; cold start → Home |
| Selected header tab per library | Session only; cold start → Recommended |
| Browse filter chips / sort | Persisted per library per profile (as today) |
| Rail expanded/collapsed | Never persisted; derived from focus |
| Row scroll/focus memory | In-memory per screen visit (existing) |

Library rows show skeleton counts (`—`) until loaded; a library with zero
items keeps its row with the standard empty state on its page.

---

## 9. API & server notes

Rail's headline advantage: **no merged scopes, no new server work.** Existing
libraries, sections, collections, calendar, and recommendations endpoints are
used as-is. Optional later nicety (flag to `silo-server`, not required): a
lightweight `upcoming this week` count for a Calendar row badge. Top Shelf and
`continuum://` deep links unchanged.

---

## 10. Implementation mapping

### tvOS

| Area | Change |
|---|---|
| `TVMainTabView` / `TVRootDestination` | Root chrome becomes the rail; destinations = Home/Search/Calendar/Settings + `library(id)` + My Stuff routes; keep the single shared `NavigationStack` |
| `TVTopMenuBar` | Replaced by new `TVRail` (strip + panel + focus bridging); profile dropdown logic folds into the panel's profile block |
| `TVLibraryActionsModal` / `TVLibraryActionsPanel` | Delete |
| `TVLibrariesTabView` | Becomes the per-library page controller: header tabs + chips |
| `TVLibraryLandingView` | `recommended` mode → Recommended tab; `collections` mode → Collections tab; `TVLibraryModeSlider` deleted |
| `TVLibraryGridView` + `TVAlphabetRail` | Browse tab body, unchanged behavior |
| `HomeView` | Append recommendation rows after Continue Watching |

### Android TV

| Area | Change |
|---|---|
| `TvMainRoute` / `TvMainShell` | Routes per rail row incl. `library/{id}` + Calendar |
| `TvTopMenuBar` | Replaced by new rail composables (strip + panel; `tv.material3` `NavigationDrawer` may be used **only if** it satisfies §7.3's guards — otherwise custom, matching tvOS) |
| `TvLibrariesScreen` / `TvFullScreenPicker` (library use) | Delete; `TvLibraryDetailScreen` becomes the page with header tabs |
| New: Calendar screen | Parity phase |
| `TvHomeScreen` | Append recommendation rows after Continue Watching |

### Suggested phasing

1. **Phase 1 — the rail:** strip + panel + focus model + flat library rows +
   My Stuff + For You fold; library pages keep their current internals.
2. **Phase 2 — library header:** content tabs + chips replace the mode
   slider; Genres tab; A–Z integration.
3. **Phase 3 — polish & parity:** counts/badges, first-run hint (`◀ MENU`
   affordance shown once), motion pass, Android Calendar.

### Acceptance checklist

- [ ] Any library reachable from anywhere in ≤2 presses + ≤4 down-moves, no modal.
- [ ] Rail open→right restores focus to the exact prior item, 100% of the time.
- [ ] Continuous-swipe input cannot open the rail from a row interior (§7.3.4).
- [ ] No content reflow on expand/collapse; 60 fps during the transition.
- [ ] Back/Menu chain per §7.2; never trapped, including with the panel open.
- [ ] Header tabs commit on press only; focus traversal never changes content.
- [ ] VoiceOver/TalkBack: rail announced as a menu ("Movies, 4 of 9"), current
      root announced as selected; Reduce Motion honored per §4.2.
- [ ] iOS and macOS targets build and behave unchanged.

---

## 11. Open questions

1. Collapsed-strip glyph for multiple same-type libraries: repeat the type
   icon (spec'd) or allow per-library custom icons from server metadata?
2. Should the panel show server switcher inline (Android multi-server) or
   keep it in Settings (spec'd)?
3. Calendar row count badge: worth the endpoint addition, or drop?
4. Wordmark: panel profile block only (spec'd), or also a glyph above the
   collapsed avatar?
