# Silo Cast Remote (iOS → tvOS)

Peer-to-peer LAN remote control: an iPhone discovers a Silo Apple TV on the
local network, connects directly to it, and drives playback (launch, transport,
tracks, quality, speed, aspect/HDR, **volume/mute**, **next episode**) from a
native now-playing screen. There is no server involvement — the channel is
Apple-only and LAN-local.

## Architecture

| Layer | Type | Role |
|-------|------|------|
| Wire protocol | `Cast/SiloCastProtocol.swift` | Message enum + Codable framing; `version`, `serviceType = _silocast._tcp` |
| Transport | `Cast/SiloCastSession.swift` | `actor` over `NWConnection` (TLS-PSK), TLV-framed JSON, **ordered outbound queue** |
| Phone controller | `Cast/iOS/SiloCastController.swift` | `@Observable` session state machine: connect, heartbeat, auto-reconnect, command send |
| Phone clock | `Cast/iOS/RemotePlaybackClock.swift` | Interpolates time between snapshots + optimistic transport overrides |
| Phone UI | `Cast/iOS/SiloCastRemoteControlView.swift`, `SiloCastMiniBar.swift`, `SiloCastTargetPickerView.swift`, `SiloCastControlModeButton.swift`, `SiloCastArtwork.swift` | Now-playing remote, persistent mini-bar, target picker, artwork |
| TV receiver | `Cast/tvOS/TVCastReceiver.swift` | `@Observable` singleton: `NWListener` advertise, accept, apply controls, broadcast state, standby |
| TV standby | `Cast/tvOS/TVCastStandbyView.swift`, `TVCastStandbyState.swift` | "Ready for <phone>" screen when connected but idle |

Player integration: the tvOS player registers with `TVCastReceiver` on appear
(`PlayerView`); controls are applied via `PlayerViewModel.applySiloCastControl(_:)`
and state is published via `PlayerViewModel.makeSiloCastPlaybackState(contentId:)`.

## Message protocol

`SiloCastMessage` (Codable, tagged by `type`, carries protocol `v`):

- `hello` — identity exchange (role phone/tv, deviceName/id, serverId/Name, supportedVersions)
- `launch` — phone asks the TV to start playing a `SiloCastPlaybackRequest`
- `control` — `SiloCastControlCommand` (play/pause/seek/stop, select audio/subtitle, speed, quality, video gravity, HDR, **set_volume**, **set_muted**, **play_next**)
- `state` — `SiloCastPlaybackState` snapshot (TV → phone, ~2 Hz while playing)
- `error` — coded error (`server_mismatch`, `unauthorized`, `player_not_ready`, …)
- `ping` / `pong` — heartbeat
- `close` — graceful disconnect

### Ordering
All non-hello sends go through `SiloCastSession.enqueue(_:)`, drained by a single
internal task, so state snapshots and commands cannot reorder on the wire (a
stale snapshot can never overwrite a fresh one). The initial `hello` uses the
awaitable `send(_:)` and is always sent before any `enqueue`.

### Liveness, takeover, reconnect
- **Heartbeat:** each side pings every 3 s and tears down after ~12 s of no
  inbound traffic. Any inbound message (state, command, ping, pong) counts as alive.
- **Takeover:** a new controller connection evicts the existing one
  (`closeActiveSession`) rather than being rejected — a dropped phone can always
  reconnect, and there is no single-session lockout.
- **Auto-reconnect:** on a transport drop the phone shows "Reconnecting…" and
  retries with 1–5 s backoff (up to 5 attempts), preserving the target. An
  intentional `.close` (takeover or user disconnect) clears the target so it
  does **not** reconnect.
- **Graceful close:** intentional disconnects enqueue `.close` (ordered after
  pending sends) then tear down after a bounded 300 ms flush window, so the peer
  gets a clean app-level signal without the close being able to hang.
- **Re-advertise:** the TV re-advertises its Bonjour service when the active
  server changes, so phones on the new server can find it (and stale phones cannot).

## Volume control — important platform constraint

tvOS exposes **no system/TV-volume API**: `MPVolumeView` is not in the tvOS SDK
and `AVAudioSession.outputVolume` is read-only. The remote therefore controls
**per-player playback gain**, not system volume:

- **`PlayerCore` route** (custom decoder → `AVAudioEngine`): gain is applied to
  the engine's `mainMixerNode.outputVolume`. This always works because PlayerCore
  decodes to PCM. The gain is re-applied after every engine reset/route change so
  it survives format changes.
- **`AVPlayer` route:** gain is applied via `avPlayer.volume`. This attenuates
  **decoded PCM only** — it is a **no-op when audio is bitstreamed/passthrough**
  (Dolby Digital/Atmos to a receiver) or routed via AirPlay. User-mute is modeled
  as `volume = 0`, **never** `avPlayer.isMuted` (that property is reserved for the
  player's initial-video-display gate and would clobber a user mute).

Consequences, surfaced honestly in the UI:
- The slider attenuates **0–100 % of the current TV volume** and **cannot boost
  above it** (there is no amplification).
- The cast state echoes the *applied* gain value, which on a passthrough AVPlayer
  route may not correspond to an audible change.

## Security — known limitation (deferred)

The cast channel uses **TLS-PSK with a single static pre-shared key compiled into
every build** (`SiloCastSession.tlsParameters()`). The channel is therefore
**encrypted but not authenticated**: the only authorization is the `serverId`
match performed in the `hello` handshake. Hardening added in this work makes that
check **fail-closed** (missing/empty/mismatched `serverId` is rejected; `.launch`
and `.control` are refused until a session is `isAuthorized`; an unauthorized
session is closed by a 5 s watchdog). That is consistency/defense-in-depth — it
is **not** real authentication: any device on the LAN running a Silo build can
control any Silo TV bound to the same server.

**Deferred follow-up (recommended):** derive a per-pair / per-server secret from
the existing companion-pairing trust (`_silopair`, see the pairing flow) and bind
it into the cast `hello` handshake (e.g. HMAC the hello/launch with the per-pair
secret, or a one-time PIN echoed from the TV), so only paired devices can control
the TV. Until then, treat LAN access as the trust boundary.

## Testing

Shared logic round-trips and the `RemotePlaybackClock` interpolation/optimistic
math are documented as XCTest cases in `iosApp/Tests/SiloCastTests.swift`. Note:
the XcodeGen project does **not** currently wire a unit-test target, so these are
not compiled/executed — wiring a `SiloTests` target is a recommended follow-up.
End-to-end behavior is verified with two simulators sharing the host network
(see the `companion-pairing-sim-test` notes for the Bonjour/TLS sim-to-sim setup).
