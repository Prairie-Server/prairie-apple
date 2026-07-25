# Native-style companion pairing card (iOS)

**Date:** 2026-06-14
**Branch:** feature/companion-pairing
**Status:** Approved design — ready for implementation plan

## Summary

Replace the top "Set up Apple TV" banner on iOS with a card that rises from the
bottom of the screen, dimming the app behind it, in the style of Apple's native
proximity-setup experience (AirPods / new Apple TV). The **entire** companion
pairing flow — including server selection and match-code confirmation — runs
inside that one card, rather than the banner opening a separate full-screen
sheet.

This is an iOS-client + tvOS-client change only. The pairing protocol,
`CompanionPairingCoordinator`, `PairingSession`, and all server behavior are
unchanged, except for one backward-compatible addition to the tvOS Bonjour TXT
record (a per-session nonce, see §3).

## Motivation

Today (`SetUpTVBanner.swift`) a discovered blank Apple TV surfaces as a banner
pinned to the top safe area; tapping "Set Up" opens `TVPairingView` as a
`.sheet`. The banner reads like an app notification rather than a system pairing
prompt, and the flow then jumps into a separate modal. The goal is a single,
native-feeling surface that handles discovery through completion in place.

## Current state (what exists)

- `Pairing/Companion/TVPairingBrowser.swift` — browses `_prairiepair._tcp`,
  publishes `[DiscoveredTV]`. `DiscoveredTV` carries `id` (stable device id),
  `name`, `state`, `endpoint`.
- `Pairing/Companion/SetUpTVBanner.swift` — `SetUpTVBannerModifier`, a
  `safeAreaInset(edge: .top)` banner + a `.sheet` presenting `TVPairingView`.
  Applied in `ContentView` via `.setUpTVBanner()`.
- `Pairing/Companion/TVPairingView.swift` — the modal flow; switches on
  `CompanionPairingCoordinator.State` to render connecting / server picker /
  confirm code / working / finished / error.
- `Pairing/Companion/CompanionPairingCoordinator.swift` — drives the phone side.
  `State` enum: `.connecting`, `.pickServers(tvName,servers)`,
  `.confirmMatch(tvName,serverName,matchCode)`, `.working(progress)`,
  `.finished(signedIn,failed)`, `.error(String)`. **Unchanged by this work.**
- `Pairing/Receiver/TVPairingAdvertiser.swift` (tvOS) — advertises the service
  with TXT fields `v`, `name`, `id`, `st`. Lifecycle owned by
  `TVServerSetupView`; the listener runs only while the TV sits on its setup
  screen, so the service appears/disappears as the TV enters/leaves setup.

## Design

### 1. Presentation: bottom card overlay

Replace the top-banner modifier with a bottom-anchored card overlay applied to
the same root view in `ContentView`.

- Rename the modifier and entry point: `SetUpTVBannerModifier` →
  `CompanionPairingCardModifier`; `.setUpTVBanner()` → `.companionPairingCard()`.
  (Single call site in `ContentView`.)
- Structure: a `ZStack`/overlay containing
  1. a dimming **scrim** (`Color.black.opacity(~0.45)`, ignores safe area)
     that fades in with the card; tapping it is equivalent to "Not Now" while on
     the discovery step (and is disabled / requires explicit choice once the
     flow is underway — see §2),
  2. the **card** pinned to the bottom, using a blur material background,
     rounded corners (~30pt), a grabber, and internal padding matching the
     approved mockups.
- Animate in/out with `.move(edge: .bottom).combined(with: .opacity)` and a
  spring, replacing the current top-edge transition.
- Use a **custom overlay, not `.sheet`**. Rationale: full control over the card
  chrome (grabber, hero, blur, exact corner radius) to match the native look,
  and the ability to swap the body between steps without sheet
  dismissal/re-presentation. (`.presentationDetents` on a `.sheet` was
  considered but rejected for less chrome control and step-swap friction.)
- The card auto-presents when there is a `candidate` (a discovered TV in
  `.setup` state whose dismissal key is not in the dismissed set — see §3).

### 2. Card content driven by coordinator state

The card is one container with a **consistent header** (Apple TV hero glyph +
title) and a **body that swaps by step**. The pre-connection discovery step is
owned by the card; once the user taps **Set Up**, the body is driven by
`CompanionPairingCoordinator.State`:

| Step | Source | Body |
|------|--------|------|
| Discovery | card-local (pre-coordinator) | Hero + "Set Up Apple TV" + device name + **Set Up** / **Not Now** |
| `.connecting` | coordinator | Spinner — "Connecting to {name}…" |
| `.pickServers` | coordinator | **Server selection rows** in-card: per server an icon + name + trailing circular checkmark that fills blue when selected; multi-select; **Continue** disabled until ≥1 selected |
| `.confirmMatch` | coordinator | Large, letter-spaced match code + "for {serverName}" + **Yes, this matches** / **Doesn't match** |
| `.working` | coordinator | Progress text/spinner |
| `.finished` | coordinator | Success summary (signed-in / failed) + **Done** |
| `.error` | coordinator | Message + **Close** |

Tapping **Set Up** runs the session-bootstrap logic currently in
`TVPairingView.task`: construct `PairingSession(endpoint:)`, `open()` the stream,
build the `CompanionPairingCoordinator`, and `begin()`. On dismissal/cancel,
call `coordinator.cancel()` as today.

`TVPairingView` is effectively folded into the card. Its existing per-step
subviews are restyled to the card's visual language (server picker rows,
match-code display, finished/error) rather than rewritten; the coordinator
contract is untouched. The standalone `TVPairingView` type is removed once its
content lives in the card (no other call sites).

Once the flow is past the discovery step, dismissal is by explicit control
(Cancel/Done/Close within the body); scrim-tap no longer silently cancels an
in-progress pairing. Exact treatment: scrim tap is a no-op (or a gentle bounce)
once connected; the discovery step keeps scrim-tap = Not Now.

### 3. Dismissal until the TV re-advertises (session nonce — option B)

Goal: "Not Now" hides the card for that Apple TV until the TV **starts a new
setup session** (it re-advertises from scratch), not forever and not merely for
the app session.

The advertised `id` is a stable device id, so it cannot by itself distinguish a
continuing setup session from a restarted one. Add a per-session nonce.

- **tvOS — `TVPairingAdvertiser.swift`:** add a `sid` field to the TXT record,
  generated fresh on each `start()` call (a random token, e.g.
  `UUID().uuidString`). All existing fields (`v`, `name`, `id`, `st`) unchanged.
  `start()` runs when the TV's setup screen appears (`TVServerSetupView.task`),
  so a new `sid` is minted when the TV reboots or leaves and re-enters setup.
  **Granularity note:** within one setup session the `sid` is *stable* — after a
  pairing attempt the receiver calls `release()` (same listener, same `sid`),
  not `start()`. So "Not Now" stays dismissed for the whole time the TV sits on
  its setup screen, and re-presents only when that screen restarts. This is the
  intended, no-nag behavior; per-attempt re-prompting is an explicit non-goal
  (see §6 for an optional future refinement).
- **iOS — `TVPairingBrowser.swift` / `DiscoveredTV`:** parse `sid` from the TXT
  record; add `sid: String?` to `DiscoveredTV` (optional for older TVs that
  don't advertise it).
- **iOS — dismissal logic (card modifier):** track dismissals as a `Set<String>`
  of **dismissal keys**, where the key is `"\(id)#\(sid)"` when `sid` is
  present, and `id` alone when it is absent (fallback for older TVs). "Not Now"
  inserts the current candidate's key. A TV is a candidate only if its current
  key is not in the set.
  - New setup session (TV reboot / re-enter setup) → new `sid` → new key → card
    re-presents. ✔
  - Same setup session (later pairing attempt, or a brief Bonjour flap where the
    service drops and returns) → same `sid` → same key → stays dismissed. ✔
  - Older TV without `sid` → behaves like "dismiss for this app session" keyed
    on `id`. ✔

A small helper that computes the dismissal key from `(id, sid)` isolates this
logic for testing (§5).

### 4. Data flow

```
TVPairingBrowser (NWBrowser, _prairiepair._tcp)
  └─ found: [DiscoveredTV{ id, name, state, endpoint, sid? }]
       └─ CompanionPairingCardModifier
            ├─ candidate = first .setup TV whose key ∉ dismissed
            ├─ Discovery step → user taps Set Up
            │     └─ PairingSession(endpoint) → open() → CompanionPairingCoordinator.begin()
            ├─ body swaps on coordinator.state (pickServers → confirmMatch → working → finished)
            └─ Not Now / scrim(discovery) → dismissed.insert(key(candidate))
```

### 5. Testing

Per `CLAUDE.md`, no tests for UI changes. The one piece of pure logic worth a
focused unit test is the **dismissal-key** behavior:

- same `(id, sid)` stays dismissed after "Not Now",
- a new `sid` for the same `id` is **not** dismissed (re-presents),
- a missing `sid` falls back to keying on `id` alone.

Add only that focused test under `iosApp/Tests/`.

### 6. Out of scope / follow-ups

- **Android parity:** `prairie-android`'s TV advertiser should add the same `sid`
  to its TXT record so the Android TV client (and any cross-client browsing)
  stays aligned. Separate repo; **not** done here. The iOS `sid` fallback means
  Apple TVs that haven't shipped `sid` yet still work (session-scoped dismissal).
- **Server:** no change. The match code is already server-authoritative.
- The `CompanionPairingCoordinator` "confirm-once multi-server" accepted risk is
  pre-existing and unaffected.
- **Optional: per-attempt `sid` rotation (deferred).** Today `sid` rotates per
  *setup session* (screen restart), not per *pairing attempt* — after a
  cancelled/failed attempt the receiver returns to `.idle` keeping the same
  `sid`, so a TV that the user dismissed with "Not Now" won't re-prompt until
  its setup screen restarts. This is the intended no-nag behavior and fails safe
  (over-sticky dismissal, never spurious prompts). If finer granularity is ever
  wanted, the tvOS receiver could re-issue the listener's TXT with a fresh `sid`
  on each return to `.idle` (`TVPairingAdvertiser` + `ReceiverPairingCoordinator`).
  Not done here.

## Files touched

- `iosApp/iosApp/ContentView.swift` — `.setUpTVBanner()` → `.companionPairingCard()`.
- `iosApp/iosApp/Pairing/Companion/SetUpTVBanner.swift` → renamed/rewritten as
  the bottom card modifier (`CompanionPairingCardModifier`), incl. dismissal-key
  logic.
- `iosApp/iosApp/Pairing/Companion/TVPairingView.swift` — folded into the card;
  step subviews restyled; standalone type removed.
- `iosApp/iosApp/Pairing/Companion/TVPairingBrowser.swift` — parse `sid`; add
  `sid` to `DiscoveredTV`.
- `iosApp/iosApp/Pairing/Receiver/TVPairingAdvertiser.swift` (tvOS) — add
  per-session `sid` to TXT record.
- `iosApp/Tests/…` — focused dismissal-key test.
- Regenerate the project only if files are added/removed (`xcodegen generate`).

## Open questions

None. Design approved through §1–§5 and the option-B dismissal approach.
