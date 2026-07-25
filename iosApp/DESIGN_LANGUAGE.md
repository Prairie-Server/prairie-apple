# Prairie iOS Design Language

A design philosophy and specification guide derived from Plezy's open-source codebase. This document defines the visual language, interaction patterns, and component specifications for building the Prairie iOS client.

**Source of truth:** Values in this document are extracted from the Plezy Flutter app at `../plezy/`. When in doubt, cross-reference `lib/theme/mono_theme.dart`, `lib/utils/layout_constants.dart`, and the widget implementations.

---

## 1. Design Philosophy

### Core Principles

1. **Content is king.** The UI exists to showcase media artwork. Posters, backdrops, and thumbnails provide all the color and visual interest. The chrome around them should be near-invisible.

2. **Cinematic immersion.** The app should feel like a theater, not a settings panel. Deep black backgrounds, full-bleed imagery, dramatic gradients, and generous use of negative space create a premium viewing experience.

3. **Minimal chrome.** Reduce UI decoration to the absolute minimum. Zero elevation on cards. No visible card borders. No gratuitous shadows. Let spacing and contrast do the work. Plezy explicitly sets `elevation: 0` on all cards and buttons, and uses `NoSplash.splashFactory` to remove Material ripple effects.

4. **Monochrome UI, colorful content.** The UI itself is strictly grayscale — white text on dark surfaces. The primary color *is* the text color. There is no blue, no accent tint. Interactive states are communicated through white/opacity contrast, shape (pills), and context — not color coding. All visual color comes from the media artwork itself.

5. **Progressive disclosure.** Show essential info first (poster, title, year). Reveal detail (synopsis, cast, episodes) as the user drills in. Never overwhelm on the surface.

---

## 2. Color System

### Background Tiers (OLED Dark Mode)

Plezy uses an OLED-optimized dark palette. We adopt the same approach — pure black backgrounds with very subtle surface differentiation.

| Token | Hex | Plezy Source | Usage |
|-------|-----|-------------|-------|
| `background` | `#000000` | `mono_theme.dart:9` (oled.bg) | Root screen background |
| `surface` | `#0A0A0A` | `mono_theme.dart:10` (oled.surface) | Cards, elevated containers, bottom sheets |
| `surfaceContainer` | `#0E0F12` | `mono_theme.dart:16` (dark.bg, used as surfaceContainerLow) | Fallback/secondary surface |
| `outline` | `#1FFFFFFF` | `mono_theme.dart:11` | Dividers, borders (white @ 12%) |

### Text Colors

| Token | Value | Plezy Source | Usage |
|-------|-------|-------------|-------|
| `text` | `#EDEDED` | `mono_theme.dart:12` | Primary text — titles, headings, active labels |
| `textMuted` | `#EDEDED` @ 60% | `mono_theme.dart:13` (`0x99EDEDED`) | Metadata, descriptions, inactive labels |

Key: Plezy uses only **two** text colors. No tertiary. Secondary text is simply `text` at 60% opacity.

### Semantic Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `error` | `#B00020` | Error states (Plezy `mono_theme.dart:55`) |
| `success` | green (Material `Colors.green`) | Download complete indicators |
| `warning` | amber (Material `Colors.amber`) | Paused states, ratings stars |

### Key Rule: Primary = Text Color

Plezy's `colorScheme.primary` is set to the *text* color (`#EDEDED`), not a brand accent. This means all "primary" UI elements (buttons, progress indicators, focus rings) are white/light gray. The `onPrimary` is the background color, creating an inverted button style.

---

## 3. Typography

### Type Scale

Plezy uses the system font (Material's `Typography.englishLike2021`; for iOS this maps to SF Pro). Hierarchy comes from **weight and size**, not color or decoration.

| Token | Size | Weight | Letter Spacing | Plezy Source | Usage |
|-------|------|--------|----------------|-------------|-------|
| `heroTitle` | `displaySmall` (~36pt) | Bold (w700) | -0.5 | `discover_screen.dart` | Title overlaid on hero backdrop |
| `appBarTitle` | 18pt | Bold (w700) | -0.2 | `mono_theme.dart:85` | App bar titles |
| `sectionTitle` | `titleMedium` (~16pt) | Semibold (w600) | 0 | `mono_theme.dart:92` | Section headers ("Continue Watching") |
| `cardTitle` | `titleSmall` (~14pt) | Bold | 0 | `media_card.dart` grid card text | Title below poster cards |
| `body` | `bodyMedium` (~14pt) | Regular | 0 | `mono_theme.dart:93` | Descriptions, synopses |
| `metadata` | `bodySmall` (~12pt) | Regular | 0 | `mono_theme.dart:94`, `episode_card.dart:68` | Year, runtime, captions |
| `episodeNumber` | 11pt | Semibold (w600) | 0 | `episode_card.dart:349` | Episode badges ("E1") |
| `tabLabel` | 11pt | Regular | 0 | `mono_theme.dart:133` | Bottom nav labels |

### Typography Rules

- **Hero titles** use `displaySmall` weight bold with a text shadow (`surface` color @ 80% alpha, 8pt blur radius) for legibility on images.
- **Metadata uses interpuncts** (`·`) as separators with 6pt horizontal padding: `Movie · ★ 9.2 · PG-13 · 2017`
- **Episode summaries** get 1.3 line height for readability (`episode_card.dart:379-380`).
- **Line limits**: Card titles = 2 lines max. Episode titles = 2 lines. Episode descriptions = 3 lines (collapsible on non-TV). Body text on detail screens = unlimited.

---

## 4. Spacing & Layout

### Design Tokens

| Token | Value | Plezy Source | Usage |
|-------|-------|-------------|-------|
| `radiusSm` | 8pt | `mono_tokens.dart:9` | Cards, posters, thumbnails, buttons, inputs |
| `radiusMd` | 12pt | `mono_tokens.dart:10` | Input borders, dialogs |
| `cardRadius` | 14pt | `mono_theme.dart:98` (CardTheme) | Card containers |
| `space` | 12pt | `mono_tokens.dart:11` | Base spacing unit |
| `pillRadius` | StadiumBorder | `mono_theme.dart:41` | All pill-shaped buttons |

### Screen Layout

- **Horizontal content padding**: 12pt (hub section leading padding, `hub_section.dart:87`).
- **Card internal padding**: 3pt all sides for grid cards (`media_card.dart` grid builder).
- **Episode card padding**: 8pt horizontal, 6pt vertical (`episode_card.dart:144`).
- **Grid padding**: 2pt left, 2pt right, 2pt bottom (`layout_constants.dart`).
- **Grid cross-axis spacing**: 0pt (cards use their own internal padding).

### Poster Card Widths by Density

| Density | Mobile | Tablet | Desktop |
|---------|--------|--------|---------|
| Comfortable | 180pt | 210pt | 250pt |
| Normal | 155pt | 185pt | 220pt |
| Compact | 120pt | 140pt | 160pt |

**Poster aspect ratio**: `2 / 3.3` (slightly taller than standard 2:3).

---

## 5. Component Specifications

### 5.1 Hero Carousel (Discover Screen)

The centerpiece of the home screen. A full-width, auto-advancing carousel of featured content.

```
┌─────────────────────────────────┐
│                                 │  ← Backdrop image, full-bleed,
│                                 │     extends behind status bar
│                                 │     with parallax (0.3x scroll)
│                                 │
│  MOVIE TITLE                    │  ← displaySmall, bold, white
│  Movie · ★ 9.2 · PG-13 · 2017  │     with text shadow
│                                 │
│  ┌─ ▶ ════░░░ 92 min left ──┐  │  ← Pill play button
│                                 │
│  ■■ ○ ○ ○ ○                    │  ← Animated page indicator
└─────────────────────────────────┘
```

**Specifications (from `discover_screen.dart`):**
- **Height**: `500pt + statusBarHeight` (mobile), or `75% of screen height` (with side nav)
- **Auto-advance**: Every 8 seconds (`_heroAutoScrollDuration`)
- **Image animation**: 800ms easeOut fade-in, with subtle scale `1.0 + (0.1 * (1 - value))` during entrance
- **Parallax**: Scroll offset * 0.3

**Gradient overlay:**
- LinearGradient, top to bottom
- Colors: `[transparent, background @ 90%, background @ 100%]`
- Stops: `[0.5, 0.85, 1.0]`
- Bottom extends -4pt past the stack bounds to prevent sub-pixel gaps

**Title positioning:**
- Bottom padding: 50pt (mobile), 80pt (large screen)
- Horizontal padding: 24pt (mobile), 40pt (large screen)
- Logo container: 120pt height, 400pt max width

**Page indicator:**
- Position: 16pt from bottom
- Active dot: Expands to `dotSize * 3` (animated progress fill)
- Inactive dot: Circle at `dotSize`, `onSurface @ 40%`
- Active color: `onSurface @ 100%`
- Border radius: `dotSize / 2`
- Spacing: 4pt between dots

### 5.2 Media Card (Poster)

Used in horizontal rows and grid views.

```
┌──────────────┐
│              │  ← Poster image, 2:3.3 ratio
│              │     ClipRRect, 8pt radius
│              │     No border, no shadow
│              │
│    [████]    │  ← Progress bar at bottom (if in-progress)
└──────────────┘
  Title           ← titleSmall, bold, 2-line max
  2019            ← bodySmall, textMuted
```

**Specifications (from `media_card.dart`):**
- **Corner radius**: 8pt (`tokens.radiusSm`)
- **Card padding**: 3pt all sides (grid mode)
- **InkWell border radius**: 8pt
- **Elevation**: 0 (no shadow)
- **No border, no card background** — image sits directly on screen background

**Progress bar (in-progress items):**
- Positioned at bottom of poster image
- ClipRRect with only bottom corners rounded (8pt)
- Height: 4pt (`MediaProgressBar.minHeight`)
- Track color: `surfaceContainerHighest`
- Fill color: `primary` (which is the text color — white)

**Watched indicator:**
- Top-right corner (4pt inset) on episode thumbnails
- Circle with `text` color background, checkmark icon in `bg` color
- Size: 12pt icon inside padded circle
- Drop shadow: `black @ 30%`, 4pt blur

### 5.3 Horizontal Media Row (Hub Section)

A section with a title and horizontally scrolling poster cards.

**Specifications (from `hub_section.dart`):**
- Leading padding: 12pt
- Inter-card spacing: Handled by card's internal 3pt padding (effectively ~6pt gap)
- Scroll: Horizontal, no visible scroll indicator
- Cards peek the trailing edge to imply scrollability

### 5.4 Browse Grid

Library browsing in a grid layout.

**Specifications (from `layout_constants.dart`):**
- **Grid cross-axis spacing**: 0pt
- **Grid main-axis spacing**: 0pt
- **Grid padding**: 2pt left/right/bottom
- **Columns**: Calculated from card width — typically 3 on iPhone (compact density = 120pt cards)
- **Filter chips**: Pill-shaped (StadiumBorder), `secondaryContainer` background

### 5.5 Item Detail Screen

Detail view for movies and series.

```
┌─────────────────────────────────┐
│ ←                               │  ← Back button
│                                 │
│    (blurred art / backdrop)     │  ← 60% of screen height
│                                 │
│  Title Text                     │  ← displaySmall, bold, shadow
│                                 │
│  ┌ 2022 ┐ ┌ TV-MA ┐ ┌ 50m ┐   │  ← Metadata chips
│                                 │
│  ┌──── ▶ S1E1 ────┐  ⤧  ⬇  ✓  │  ← Action buttons
│                                 │
│  Overview                       │
│  Description text...            │
│                                 │
│  Seasons                        │
│  [Season tabs]                  │
│  [Episode list]                 │
└─────────────────────────────────┘
```

**Backdrop (from `media_detail_screen.dart`):**
- **Max height**: `screenHeight * 0.6` (60% of screen)
- **Image**: Blurred artwork (art image, not backdrop)
- **Gradient**: LinearGradient top → bottom
  - Colors: `[transparent, background @ 90%, background]`
  - Stops: `[0.3, 0.8, 1.0]`
  - Bottom extends -1pt

**Title:**
- `displaySmall`, bold, white
- Text shadow: black @ 50%, 8pt blur radius
- Logo container: 120pt height, 400pt width, left-aligned

**Metadata chips:**
- Pill-shaped (full corner radius = `Radius.circular(100)`)
- Background: `secondaryContainer @ 80%`
- Padding: 12pt horizontal, 6pt vertical
- Spacing: 8pt between chips
- Animation: 150ms easeOutCubic on appearance

**Primary play button:**
- **Background**: `Colors.white` (solid white)
- **Foreground**: Black text/icon (inverted)
- **Shape**: Pill (StadiumBorder), `Radius.circular(24)`
- **Padding**: 24pt horizontal, 12pt vertical
- **Progress bar inside button** (if in-progress):
  - Height: 6pt
  - Track: `Colors.black26`
  - Fill: `Colors.black`
  - Border radius: 2pt

**Secondary action buttons**: Icon-only circles, same color scheme.

### 5.6 Episode Card

List of episodes within a season.

**Specifications (from `episode_card.dart`):**
- **Container**: `surfaceContainerLow` background, rounded 8pt (`FocusTheme.defaultBorderRadius`)
- **Padding**: 8pt horizontal, 6pt vertical
- **Vertical spacing between cards**: 2pt (`Padding symmetric vertical: 2`)

**Thumbnail:**
- Width: 160pt
- Aspect ratio: 16:9
- Corner radius: 6pt (slightly less than standard 8pt)
- Gradient overlay: transparent → `black @ 20%`, top to bottom

**Play button overlay:**
- Centered on thumbnail
- Circle: `black @ 60%` background
- Icon: `play_arrow_rounded`, filled, white, 20pt
- Padding: 6pt inside circle

**Progress bar (in-progress):**
- Bottom of thumbnail, clipped to bottom corners (6pt radius)
- Height: 3pt (`LinearProgressIndicator minHeight: 3`)
- Track: `tokens.outline`
- Fill: `primary`

**Episode number badge:**
- Background: `primaryContainer`
- Text: `onPrimaryContainer`, 11pt, semibold (w600)
- Padding: 6pt horizontal, 3pt vertical
- Border radius: 3pt

**Episode title**: `titleSmall`, bold, 2-line max
**Summary**: `bodySmall`, `textMuted`, 1.3 line height, 3-line max (collapsible)
**Metadata row**: 12pt, `textMuted`, interpunct separators with 6pt padding

### 5.7 Tab Bar / Bottom Navigation

**Specifications (from `mono_theme.dart:129-138`):**
- **Background**: `bg` color (no elevation, no blur — unlike iOS convention)
- **Elevation**: 0
- **Indicator**: Transparent (no selection indicator)
- **Icon size**: 22pt
- **Icon opacity**: Active = 1.0, inactive = 0.6
- **Icon color**: `text` (same for both states, opacity distinguishes)
- **Label**: 11pt, `textMuted` color

### 5.8 Filter Chips / Tab Chips

**Specifications (from detail screen + browse views):**
- **Shape**: StadiumBorder (full pill)
- **Selected**: `text` color background, `bg` color text
- **Unselected**: `surface` background, `text` color text
- **Border radius for season tabs**: 8pt (`tokens.radiusSm`)

### 5.9 Buttons

**Specifications (from `mono_theme.dart:35-41`):**
- **Shape**: StadiumBorder (pill) for all elevated/filled buttons
- **Padding**: 18pt horizontal, 14pt vertical
- **Background**: `text` color (inverted — white button on dark bg)
- **Foreground**: `bg` color (dark text on white button)
- **Elevation**: 0
- **No ripple**: `NoSplash.splashFactory`

---

## 6. Image Treatment

### Backdrops / Hero Images

- **Loading**: Fade-in with 800ms easeOut animation, slight scale animation (1.1 → 1.0)
- **Gradient**: Always applied. Three-stop gradient blending into background:
  - Stops at `[0.5, 0.85, 1.0]` for hero; `[0.3, 0.8, 1.0]` for detail
  - Final color matches `background` exactly (no visible seam)
- **Parallax**: scrollOffset * 0.3 on hero

### Posters

- **Corner radius**: 8pt everywhere (`tokens.radiusSm`)
- **Loading state**: `surfaceContainerHighest` placeholder (from `PlaceholderContainer`)
- **Error state**: Same placeholder with centered icon (movie icon, 32pt, filled)
- **No border, no shadow**: Zero elevation, cards blend with background

### Thumbnails (Episodes)

- **Corner radius**: 6pt (slightly less than poster 8pt)
- **Spoiler protection**: `ImageFilter.blur(sigmaX: 12, sigmaY: 12)` when hide-spoilers is enabled
- **Play overlay**: Always visible, `black @ 60%` circle with white play icon
- **Progress bar**: 3pt at bottom, only bottom corners rounded

---

## 7. Motion & Animation

### Duration Tokens (from `mono_tokens.dart`)

| Token | Duration | Usage |
|-------|----------|-------|
| `fast` | 120ms | Focus state changes, hover effects |
| `normal` | 200ms | Tab transitions, chip selection |
| `slow` | 300ms | Image crossfades, content reveals |

### Specific Animations

- **Hero image entrance**: 800ms easeOut (fade + scale)
- **Carousel auto-advance**: Every 8 seconds
- **Metadata chip appearance**: 150ms easeOutCubic
- **Focus scale**: 1.02 (2% scale up) with focus border
- **Focus border**: 2.5pt width, `primary` color, animated at `fast` speed

### Interactive Feedback

- **Tap**: `NoSplash` — no ripple effect. Relies on navigation feedback.
- **Focus ring**: 2.5pt border in `primary` color, 8pt border radius, with 2% scale
- **Hover**: `surface @ 5%` overlay (`episode_card.dart:138`)

---

## 8. Dark Mode

The app is **dark-only** (OLED mode). There is no light mode for the streaming interface.

- Force dark mode: `overrideUserInterfaceStyle = .dark` on root window
- Background is pure `#000000` for true OLED black
- Surface is barely visible `#0A0A0A` — cards are felt, not seen

---

## 9. Accessibility

- All interactive elements: 44x44pt minimum touch target
- Episode thumbnails: meaningful labels including episode number, title, and progress state
- Focus system: Clear 2.5pt border ring with scale feedback
- Text on images: Always backed by gradient + text shadow for contrast
- Dynamic Type: Respected for body text; display titles may remain fixed

---

## 10. Screen Reference

### Home (Discover)

- Top: Screen title (18pt bold, left-aligned), right icons for profile/refresh
- Hero: 500pt + status bar height, auto-advancing, with parallax
- Below: Hub sections — "Continue Watching", "Recently Added", etc.
- Pull-to-refresh supported

### Libraries (Browse)

- Library selector with dropdown
- Tab chips: Recommended / Browse / Collections
- Filter chips below tabs
- Content: Grid of poster cards, density-responsive sizing

### Item Detail

- Backdrop: 60% screen height, blurred art
- Title: displaySmall bold on gradient
- Metadata: Pill chips
- Play button: **White pill** with dark text (inverted from typical dark UI)
- Sections: Overview, Seasons (tabs), Episodes, Cast

### Episode List

- Horizontal layout: 160pt thumbnail + text info
- Container background: `surfaceContainerLow`
- 6pt thumbnail corners, 8pt container corners
- Collapsible summaries on mobile

### Settings

- Standard list style, `surface` row backgrounds on `background`
- Minimal decoration

---

## 11. Implementation Checklist

When building or reviewing a screen, verify:

- [ ] Background is pure black (`#000000`)
- [ ] Cards have zero elevation, no border
- [ ] Poster corners are 8pt, thumbnail corners are 6pt
- [ ] No blue or accent colors anywhere in UI chrome
- [ ] Buttons use inverted style (white bg, dark text) — StadiumBorder
- [ ] Text uses only `#EDEDED` (full) or `#EDEDED` @ 60% (muted)
- [ ] Gradients use 3-stop pattern: `[transparent, bg@90%, bg]`
- [ ] No Material ripple/splash effects
- [ ] Images fade in (300-800ms), no pop-in
- [ ] Episode cards have `surfaceContainerLow` background, not transparent
- [ ] Metadata uses interpuncts (`·`) with 6pt spacing
- [ ] Grid has 0pt spacing (cards handle their own 3pt internal padding)
- [ ] Dark mode forced regardless of system setting
