# AetherEngine gap remediation

**Date:** 2026-07-07
**Input:** [`docs/tvos-player/2026-07-07-aetherengine-gap-audit.md`](../../tvos-player/2026-07-07-aetherengine-gap-audit.md) — 18 verified gaps vs AetherEngine's fixed defects (audit @ `fb5272e`, code @ `359d20c`).
**Goal:** close every gap judged valid, ordered by user impact: freeze-class bugs first, A/V correctness second, platform/UX third, resilience tail last.

## Triage verdict

| Audit gap | Verdict | Where in this plan |
|---|---|---|
| 1. wedge-recovery-chain (HIGH) | **address** | A1 |
| 7. recovery-seek-anchoring | **address** (merged with A1 — same fields) | A1 |
| 5. loopback-http-server 404→503 | **address** | A2 |
| 4. restart-coalescing residency | **address** | A3 |
| 8. muxer-timestamp-continuity (#92) | **address**, verify-first | B1 |
| 9. av-gating pre-gate audio (#74) | **address** (also serves open [CMP-SEAM]) | B2 |
| 3. segment-planning flush bound (#64) | **address** | B3 |
| 6. segment-cache-retention ledger | **address** | B4 |
| 17. network-reader AVIO leak | **address** (one-liner) | B5 |
| 2. host-item-reuse / AirPlay | **address** (two-stage) | C1 |
| 13. host-transport-clock-state | **address** | C2 |
| 11. hdr-dv SDR criteria + snap | **address** | C3 |
| 15. probe-budget seek deadline | **address** | D1 |
| 10. audio-bridge swr re-derivation | **address** | D2 |
| 14. subtitle extractor throttle | **address** | D3 |
| 16. software-path SAR/black-flash/resize | **address** | D4 |
| 17b. 429 rate-limit handling | **address** | D5 |
| 18. diagnostics-tooling | **split**: park-log fixes → A1; release sink → existing playback-diagnostics plan | A1 / deferred |
| 12. native-subtitle-renditions (PiP) | **defer** — decision gates `feature/ios-pip` merge, not main | Deferred |
| 14b. CEA-608 decode | **defer** — validate-only first; no 608-only content known in library | Deferred |
| 17c. fflags +genpts | **drop** — unverified benefit; AE reverted its siblings | Dropped |

Rationale for the two deferrals: PiP subtitles only matter once `feature/ios-pip`
merges (PiP is capability-gated off on main); the right move is a merge-gate
decision recorded on that branch (default: ship v1 with a documented
no-subtitles-in-PiP limitation and hide the PiP affordance while a subtitle
track is active; the VTT-rendition build is its own future project). CEA-608
matters only for OTA-DVR-style content with in-band captions and no text
tracks — none known in the library; we only validate whether AVPlayer
auto-surfaces CC1 from the loopback fMP4 and document the result.

Every item below references the audit doc for the full AE mechanism; this plan
adds scope, ordering, dependencies, and validation. Line anchors are from the
audit (approximate).

---

## Workstream A — Recovery chain (freeze-class) · `AVPlayerBackend.swift`, `LoopbackSegmentServer.swift`

The consumer-side counterpart of the 359d20c producer fix. These interlock:
A1's seek-deadline unblocks the watchdogs that A2/A3 rely on to matter, and all
three route through the same stall-recovery ladder. **Do A1+A2+A3 as one branch**
(`fix/loopback-recovery-chain`) so recovery can be tested as a system.

### A1 — Seek deadline, item-death revive, pause reassert (audit #1 + #7 + #18a)

1. **Deadline-bound seek.** Give `seek(to:)` a per-seek generation token; arm an
   ~8–10 s timer racing the completion. On expiry classify with AE's
   `seekIsWedged` predicate (forward `loadedTimeRanges` at the target vs
   rendered time; buffered-but-frozen = wedged, climbing = healthy-slow), clear
   `isSeekPending`, keep `vodPendingSeekMediaTarget` alive as recovery intent,
   and let `loopbackPlayheadWatchdogTick` run `performVODStallRecovery` at the
   TARGET. Only the latest generation's completion may clear state; clear
   `isSeekPending` even when `seekItem !== currentItem` (latch leak); reset it
   in `load()`'s state reset.
2. **Intent lifecycle (audit #7).** Retire `vodPendingSeekMediaTarget` only when
   `finished == true` AND landed within ~5 s of the target; add staleness
   retirement (~3 s of organic progress far from the target); have
   `attemptSiloRouteCompatibilityFallback` prefer the unlanded target over the
   frozen `currentTime` when building the fallback start.
3. **Item-death revive.** In `recoverLocalLoopbackFailureIfNeeded`, treat any
   `failedToPlayToEndTime` with `!isUserPaused` as item death: bounded revive
   gate (cap ~3, reset on >0.5 s position progress) driving the existing
   in-place item-reload path with the `.paused` gating bypassed; exhaustion
   escalates to `onLoopbackStallUnrecoverable("item_death")` → Compatibility
   fallback.
4. **Spurious-pause reassert.** In the watchdog: `timeControlStatus == .paused
   && !isUserPaused && reasonForWaitingToPlay == nil` for N consecutive ticks →
   `avPlayer.play()`, capped ~3 per reanchor window. (Interruption-initiated
   pauses become real pauses via C2, so the two must land in the same release
   to avoid re-asserting through a phone call.)
5. **Watchdog dead zone.** Close `bufferedAhead >= 2 && generatedAhead < 12`
   satisfying neither arm — coordinate with the deliberately-deferred
   steady-state backpressure detector rather than duplicating it.
6. **Park-log polish (audit #18).** `waitForVODWindowIfNeeded`: start the re-log
   at ~10 s (not 0 s), add the consumer tuple (fetch target / highest stored /
   cached count) from `LoopbackSegmentStore`.

*Validation:* unit tests for the seek-generation state machine and revive gate;
sim: wedge injection (kill origin mid-seek via dev-server iptables or proxy
pause) → recovery lands at the seek target; full regression of normal
seek/scrub/pause on all 3 platforms.

### A2 — 503 + Retry-After for in-range misses (audit #5)

`classifySegmentResponse(index:segmentCount:hasData:)` pure helper (unit-tested
beside `parseByteRange`); plumb plan `segmentCount` into
`LoopbackSegmentServer`; in-plan miss → `503 Retry-After: 1`, out-of-plan →
404. Then drop `vodSegmentMissWaitSeconds` 8 s → ~2.5 s (under AVPlayer's
~3.5 s TTFB watchdog) and keep re-asserting the coalesced restart per retry.

*Validation:* unit tests for the classifier; sim with artificial producer delay
(existing tracer hooks) — AVPlayer retries instead of erroring; confirm no
-12889 accumulation in [CMP] logs.

### A3 — Residency check in covered-restart guard (audit #4)

Add `LoopbackSegmentStore.isResident(index:)` (segments, spilling, spilled,
progressive); qualify `requestVODProducerRestart`'s covered-early-return: ride
the march only when `target > producedHead` OR resident. Fire-side orphan
suppression: skip the miss-resolver restart when the missed index is outside
the newest declared target's forward window. Keep authoritative restarts
exempt.

*Validation:* store unit tests (pruned-in-window index fires restart); sim:
long-play until retention prunes, scrub back to near-base segment → plays
(regenerates) instead of 8 s-404 spiral.

**Estimated size:** the biggest workstream — A1 is the careful one; A2/A3 are
small. One focused session incl. tests, plus a wedge-injection sim pass.

---

## Workstream B — Writer correctness · `LoopbackSegmentWriter.swift`, `LoopbackSegmentStore.swift`

Independent of A; each item is separately land-able. Branch
`fix/loopback-writer-correctness` or land B4/B5 directly.

### B1 — Video duration telescoping (audit #8, AE #92) — verify first

1. *Verify reachability:* play 2–3 standard MKVs in the sim and grep stderr for
   `Packet duration` / `out of range` movenc warnings. If reproducible →
   proceed; if not reproducible on our content, downgrade to
   opportunistic-with-test and note in the audit doc.
2. *Fix:* persistent one-packet video look-behind in the mux loop — hold each
   video packet until the next arrives, set `held.duration = next.dts −
   held.dts` when positive (fallbacks: existing positive duration, then tick).
   The held packet still routes cuts by its own PTS (`vodCutBeforeVideoPacket…`
   ordering preserved) and flushes with original duration at EOF/teardown.
   Port AE's pure `resolveVideoSampleDuration` with unit tests.

*Validation:* warnings gone on the same files; frame-count parity (produced
fragment sample counts unchanged); tail frame present at EOF.

### B2 — Pre-gate audio buffering + seam ledger (audit #9, AE #74)

Restart branch of `vodShouldDropPacket`: buffer selected-audio packets (8 MiB
cap, DTS-ordered) instead of freeing while the video gate is closed; at
gate-latch, drain through the existing `dts+duration > gate` span filter.
Head-of-stream: widen `keepSelectedAudioPreroll` to `.copy` mode (the
`retainPreVideoAudioPacket` stash + replay already exists; copy-mode replay
routes through `rewritePacketForOutput`; the `vodAnchorPts` threshold already
drops below-anchor packets). Add the per-segment-open ledger line (planned
plan-start vs actual first routed DTS, drift) — this is the instrument the
open **[CMP-SEAM]** investigation needs, so land it before the next seam
hardware session. Do NOT move `setActive(true)` here — that's C2's scope.

*Validation:* sim on a chunk-interleaved MP4/MOV: `vodPrerollDroppedAudio`
telemetry ≈ 0 post-fix and first-audio arrives within one frame of the gate;
[CMP-SEAM] first-audio outPts unchanged on the One Piece repro file (no
regression of 359d20c).

### B3 — Session-long interleaver flush bound (audit #3, AE #64)

Track routed-video PTS span since last flush in `vodCutBeforeVideoPacketIfNeeded`
without the `vodProgressiveAccumulating` gate; bound ~2× target (8 s)
post-anchor, keep 1.5 s cadence inside the anchor window; keep the 359d20c
moov-wedge guard in `performVODInterimFragmentFlush`. Guard sentinel/backward
PTS like AE's `bufferedTicksExceedsBound`. Second half: cap the never-cut
first segment — when `pendingSegmentBytes` + progressive bytes exceed a budget
(~256 MB), fail the session with a typed `LoopbackWriterError` (route ladder
fallback) — spilling the progressive prefix through the PR #68 tier is a
follow-on if the fallback proves too blunt.

*Validation:* sim with a sparse-keyframe source (or trusted-gap ~30 s remux):
memory high-water via `PlayerCPUDiagnostics`/Instruments stays bounded;
multi-fragment segments still serve (anchor path already proves the shape).

### B4 — Spill ledger drift (audit #6)

`putSegment`: claim stale spill state like `retireSegments` (drop
`spillingSegments[name]`/`spilledSegments[name]`, decrement `tempSpillBytes`
via `spilledSegmentSizes.removeValue`, delete the doomed URL outside the
lock). Belt-and-braces decrement in `finishSpillLocked`. Focused test: spill N
→ `putSegment(N)` → re-spill → evict → `stats().tempSpillBytes == 0`.

### B5 — AVIO buffer leak (audit #17a)

`teardown()`: `av_free(ioContext.pointee.buffer)` (the buffer FFmpeg currently
holds, NOT the saved alloc pointer) before `avio_context_free(&ioContext)`;
fix the wrong comment. Trivial; land with B4.

**Estimated size:** one session for B1–B3 (B1 verify-first may shrink it),
B4+B5 are an hour with tests.

---

## Workstream C — Platform/UX · `AVPlayerBackend.swift`, `PlayerViewModel.swift`, `HDRDisplayCriteriaPolicy.swift`

### C1 — AirPlay + audio re-select guard (audit #2)

*Stage 1 (ship immediately, one line + guard):*
`avPlayer.allowsExternalPlayback = false` for `.siloLoopback` in
`prepareAssetPlayback` (AirPlay degrades to screen mirroring instead of a dead
127.0.0.1 session; stays `true` for receiver-reachable strategies). Early
return in `PlayerViewModel.selectAudio` when `selectedAudioId ==
track.trackId` + belt-and-suspenders compare in
`AVPlayerBackend.selectAudioTrack`.
*Stage 2 (separate follow-on plan, NOT this pass):* LAN-bind
(`0.0.0.0` + random port + unguessable session-path token — needs a security
look), `isExternalPlaybackActive` observer, LAN-IPv4 URL swap, SDR-receiver
playlist routing. Real AirPlay on the loopback route is a feature, not a bug
fix; scope it when demand shows up.

*Validation:* iPhone + real AirPlay target: mirroring works, no black-screen
receiver session; re-tapping the active audio track is a visual no-op.

### C2 — External-pause reconciliation, spurious-failed defer, rate clamp (audit #13)

1. Port PlayerCore's `installAudioSessionObservers` /
   interruption / route-change handling into `AVPlayerBackend`; route `.began`
   and `.oldDeviceUnavailable` through `pause()` so `isUserPaused` and the UI
   reconcile (also prevents `resumeLocalLoopbackPlaybackIfNeeded` auto-resuming
   into the speaker after an unplug). Reconcile an observed
   `tcs == .paused && !isUserPaused && didFireFileLoaded && !isSeekPending` by
   publishing the pause. **Must land with A1.4** (pause reassert) — they are
   two halves of one truth: reassert only pauses that are provably spurious.
2. Spurious-`.failed` defer-and-confirm: if `didFireFileLoaded`, delay
   `reportItemFailure` ~5 s; escalate only if the periodic clock advanced
   <0.5 s, guarded by item identity + a monotonic confirm token.
3. Rate clamp: video routes cap at 2.0× (`setSpeed` clamp or filter >2× from
   `PlayerSettingsSheet` for AVPlayer routes); keep 2.5/3× for audio-only.
   *(Recommendation per AE's finding that >2× video misbehaves — veto here if
   3× video is a feature you use.)*

*Validation:* iPhone sim/device: phone-call interruption + route change tests;
transient `.failed` injection (kill/restore origin) does not route-fallback
when playback self-heals.

### C3 — SDR rate-only criteria + FrameRateSnap (audit #11)

1. `HDRDisplayCriteriaPolicy` gains `.rateOnly` for SDR sources; new
   `TVDisplayCriteria.setSDRRateCriteria` (codec+rate, no BT.2020 extensions)
   with an SDR-aware settle (skip the EDR-headroom check for rate-only
   switches).
2. `FrameRateSnap` helper (snap ±0.5 to {23.976, 24, 25, 29.97, 30, 50, 59.94,
   60}, [23.5, 24.05] → 23.976, nil for VFR) applied at BOTH consumers:
   `applyTVDisplayCriteriaForLoopbackIfNeeded` refresh rate and
   `emitMasterPlaylist` FRAME-RATE. Unit tests for the snap table.
3. Cheap add-on: normalize DV `bl_compat_id == 6` → 8.1 in `outputDoviConfig`
   for `.passthroughProfile8`.
4. Stretch (only if trivial while in there): P5 canonical colr for
   unspecified-VUI sources; `appliesPerFrameHDRDisplayMetadata = true`; the
   distinct log marker for `hdrHosted=false` DV selections.

*Validation:* **hardware required** — living-room ATV with Match Frame Rate
on: 24 fps SDR film switches the panel to 24 Hz (this is the payoff of the
whole item); HDR/DV regression pass (criteria ordering is the historically
fragile part — re-run the 63a3069 validation matrix).

**Estimated size:** C1 stage 1 is minutes; C2 one focused session (shared with
A1.4); C3 one session + a hardware evening.

---

## Workstream D — Resilience tail (independent, opportunistic)

| # | Fix | Files | Notes |
|---|---|---|---|
| D1 | Bootstrap seek wall-clock deadline (audit #15): `LoopbackInterruptToken.armReadDeadline(seconds:)`, honored in the interrupt callback; arm around `prewarmVODCueIndexAndReseek` / `harvestVODPlan` / `seekInputToStartTimeIfNeeded`, deadline authoritative over seek rc; on expiry fail open (uniform/EVENT degrade) or typed error → fallback | `LoopbackInputHandoff.swift`, `LoopbackSegmentWriter.swift` | Kills the cues-less-MKV infinite spinner; sim-test with a stripped-Cues fixture |
| D2 | swr per-frame re-derivation + corrupt-frame guard + FLTP/48k seed when probe leaves `sample_fmt == NONE` (audit #10) | `LoopbackSegmentWriter.swift` | Bridged path only; DTS loopback fixture exists from the drift-governor work |
| D3 | Extractor pacing: keep one stream at `AVDISCARD_DEFAULT` as clock, move `throttleIfNeeded` above the stream-index guard, unref non-selected immediately; re-sample live playhead post-open; optional demuxer reuse across select/seek | `AVPlayerEmbeddedSubtitleExtractor.swift` | Compat-route bandwidth fix; forced-subs track over WAN is the repro |
| D4 | Software path: `kCVImageBufferPixelAspectRatioKey` from `sample_aspect_ratio` (all 3 pixel-buffer variants) + corrected `publishVideoPresentationSize`; `flush(removingDisplayedImage: false)` in `performSeek` + `setAudioTrack` restart (keep `true` in failed-layer recovery); macOS `displayLayer.autoresizingMask` | `PlayerCore.swift`, `macOS/PlayerSurface.swift` | Anamorphic DVD rip + scrub-black-flash + window-resize; each independently trivial |
| D5 | `.rateLimited(retryAfter:)` cause in `PlaybackOriginReconnectPolicy` (cap ~6, backoff = max(exp, Retry-After)); map 429 in stream + chunk fetcher | `PlaybackSourceProxy.swift` area | Matters behind rate-limiting CDNs/tunnels |

**Estimated size:** each D item is small; batch D1+D2 (writer), D3, D4, D5 as
convenient riders on the A–C branches or one cleanup pass.

---

## Deferred (recorded decisions)

- **PiP subtitles (audit #12).** Gate on `feature/ios-pip` merge review.
  Default decision: ship v1 with documented limitation + hide/disable the PiP
  affordance while a subtitle track is active; AE-style VTT rendition pipeline
  is its own future project (text tracks only — PGS/DVD can never ride it).
- **CEA-608 (audit #14b).** Validate-only: check whether AVPlayer surfaces
  in-band CC1 from the loopback fMP4 via the legible group we already load; add
  the finding to the audit doc. Build a `ClosedCaptionTap` only if real content
  shows up.
- **Diagnostics release sink (audit #18b).** Belongs to the existing
  [playback-diagnostics plan](2026-06-28-playback-diagnostics.md) — add the
  bounded release-critical line set (decoder open/fail, firstFrame, milestones,
  park/WEDGE) as a requirement there instead of duplicating a sink here.

## Dropped

- **`fflags +genpts`** — AE documents adjacent flags as tried-and-reverted and
  the RSS benefit is unverified in our pipeline. Revisit only with a measured
  RSS problem on 4K HEVC matroska.

## Sequencing & validation gates

1. **A (recovery chain)** — branch, tests, wedge-injection sim pass → PR.
   Highest severity; also de-risks every later item (failures during B–D
   testing now recover visibly instead of freezing).
2. **B (writer correctness)** — B1 verify-first; B4/B5 can land immediately.
   Sim passes per item; the B2 ledger line should land before the next
   [CMP-SEAM] hardware session.
3. **C (platform/UX)** — C1 stage 1 immediately (one-liner); C2 with A1.4; C3
   needs the hardware evening (combine with the pending 359d20c start-over
   hardware pass and the Atmos AVR pass — one living-room session covers all
   three).
4. **D** — riders/cleanup pass.

Cross-cutting: every workstream ends with the standard 3-platform build +
full test suite; A and C3 additionally get on-device passes. Update
`docs/tvos-player/2026-07-07-aetherengine-gap-audit.md` gap statuses as items
land (audit doc is the shared tracker).
