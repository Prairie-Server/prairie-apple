# Now-Playing Shelf — design

**Date:** 2026-06-16
**Branch context:** `feature/tvos-detail-redesign`
**Platform:** iOS (iPhone + iPad). Cast is iOS-only; the audio mini-player is iOS/iPadOS.

## Problem

When a cast session is active, the persistent "Playing on <TV>" mini-bar
(`SiloCastMiniBar`) floats at the very bottom of the screen and **covers the
bottom tab bar**, so taps meant for Home / Library / Search land on the mini-bar
instead. The audiobook mini-player (`AudioMiniPlayerView`) shares the same
bottom container and has the same latent overlap problem.

Root cause: both accessories are placed in a single
`.safeAreaInset(edge: .bottom)` attached to the `Group` *outside* the
`NavigationStack { TabView }` in `MainTabView` (`iosApp/iosApp/ContentView.swift`,
~lines 489–496). Because the inset attaches outside the `TabView`, the accessory
is laid into the same bottom region the `TabView` draws its tab bar into, so they
overlap.

## Goal

A persistent "now-playing shelf" that rests **directly above the bottom tab
bar** (Apple Music / Podcasts pattern). The tab bar stays fully visible and
tappable. Tapping the cast bar opens the full remote; tapping the audio bar
opens the full audio player. When nothing is playing, the shelf occupies zero
space and is not shown.

## Decisions

- **Native first, with a fallback.** Use the iOS 26 native
  `tabViewBottomAccessory(_:)` so the shelf gets the system Liquid Glass
  treatment that morphs with the tab bar. The iOS deployment target is **18.0**;
  because of Apple's version jump the only iOS versions in the wild are 18.x and
  26.x. iOS 18 gets a manual fallback (see below). Deployment target is **not**
  raised — existing iOS 18 users keep updating.
- **Single slot, cast-priority.** The native accessory area is a single compact
  row, so the shelf shows **one** accessory at a time. If both a cast session and
  an audiobook session are active simultaneously, **cast wins**; the audio bar
  shows only when there is no active cast session. This keeps the iOS 26 and iOS
  18 paths behaving identically and matches the single-accessory native model.
- **Unify, don't duplicate.** One `NowPlayingShelf` view selects and renders the
  active accessory, reusing the existing `SiloCastMiniBar` and
  `AudioMiniPlayerView` bodies. The loose cast+audio views in the outer
  `.safeAreaInset` are removed.

## Components

### `NowPlayingShelf` (new view)
- Inputs: the cast controller and the audio store (via environment, as today).
- Logic: if a cast session is active → render `SiloCastMiniBar`; else if an
  audiobook session is active → render `AudioMiniPlayerView`; else render
  nothing (no reserved space).
- Exposes whether anything is active (`isActive`) so the attachment can be gated.

### Attachment wrapper (new `ViewModifier`)
Chooses the placement mechanism for the tab layout:

```
if #available(iOS 26, *) {
    content.tabViewBottomAccessory { NowPlayingShelf(...) }   // when active
} else {
    content.safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingShelf(...) }
}
```

- Applied to the **`TabView`** inside `tabLayout` — not the outer `Group`. This
  is the fix for the overlap.
- The attachment is **gated on "is anything playing."** When idle, the modifier
  must not leave an empty Liquid Glass bar or reserved space — verify in the
  simulator. (Conditionally applying the accessory modifier based on
  `NowPlayingShelf.isActive` is acceptable; watch for animation/identity
  glitches and prefer the existing `.snappy` move-from-bottom transition.)

### iPad sidebar / macOS
The regular-width iPad sidebar and macOS use `NavigationSplitView`, which has no
bottom tab bar and no `tabViewBottomAccessory`. These layouts keep today's
behavior: attach `NowPlayingShelf` via `.safeAreaInset(edge: .bottom)` on the
sidebar layout. (macOS is audio-only; cast is `#if os(iOS)`.)

## Data flow

No protocol or server changes. The shelf reads the same observable state it does
today: `SiloCastController` (`hasActiveSession`, `isShowingRemoteControl`, clock,
state) and `AudioPlaybackStore.player` (`hasActiveSession`, metadata). Tapping
the cast bar calls `controller.showRemoteControl()`; the full remote remains a
`fullScreenCover` on `castController.isShowingRemoteControl`, unchanged. Tapping
the audio bar calls `audioStore.showFullPlayer()`, unchanged.

## Out of scope

- Adapting the accessory to the native `expanded` vs `inline`
  (`\.tabViewBottomAccessoryPlacement`) — render the standard compact bar for
  both initially; collapse-on-scroll polish can come later.
- Stacking both bars when cast + audio are active simultaneously (rejected in
  favor of single-slot cast-priority).
- Raising the iOS deployment target.

## Verification

- Build the `Silo` scheme on an **iOS 26 simulator**: start a cast session,
  confirm the shelf sits above the tab bar with the tab bar fully tappable, and
  that when idle there is no empty accessory bar.
- Build on an **iOS 18 simulator** (if an iOS 18 runtime is available): confirm
  the fallback shelf rests above the tab bar and disappears when idle. If no iOS
  18 runtime is available, at minimum compile the fallback path and review it.
- Confirm the audiobook mini-player still appears (and opens the full player)
  when only an audiobook is active.
- No unit tests — UI change, per `CLAUDE.md` testing guidance.
