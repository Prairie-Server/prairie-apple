# Apple Companion Pairing - Current Implementation Summary

- **Date:** 2026-06-14
- **Repo:** `prairie-apple`
- **Scope:** Current iOS companion plus tvOS receiver implementation
- **Note:** This summary reflects the current working tree, including local
  receiver-side edits in `ReceiverPairingCoordinator.swift` and
  `TVPairingReceiverView.swift`.

## 1. What It Does

The Apple implementation lets a signed-in iPhone set up a nearby Prairie tvOS app
without typing the server URL or password on the remote.

The TV advertises itself on the local network. The iPhone discovers the TV,
connects over a local socket, lets the user choose one or more already-signed-in
servers, confirms a server-issued match code, and approves the TV's device-login
request. The TV then receives its own access and refresh tokens from the Prairie
server over HTTPS.

Tokens never cross the LAN pairing channel.

## 2. Files

Shared pairing layer:

- `iosApp/iosApp/Pairing/PairingProtocol.swift`
- `iosApp/iosApp/Pairing/PairingFrame.swift`
- `iosApp/iosApp/Pairing/PairingSession.swift`
- `iosApp/iosApp/Pairing/PairingDeviceAPI.swift`

iOS companion:

- `iosApp/iosApp/Pairing/Companion/TVPairingBrowser.swift`
- `iosApp/iosApp/Pairing/Companion/SetUpTVBanner.swift`
- `iosApp/iosApp/Pairing/Companion/TVPairingView.swift`
- `iosApp/iosApp/Pairing/Companion/CompanionPairingCoordinator.swift`

tvOS receiver:

- `iosApp/iosApp/Pairing/Receiver/TVPairingAdvertiser.swift`
- `iosApp/iosApp/Pairing/Receiver/ReceiverPairingCoordinator.swift`
- `iosApp/iosApp/Pairing/Receiver/TVPairingReceiverView.swift`
- `iosApp/iosApp/Screens/Auth/TVServerSetupView.swift`

Supporting auth/storage:

- `iosApp/iosApp/Networking/DeviceLoginModels.swift`
- `iosApp/iosApp/Networking/TokenStore.swift`
- `iosApp/iosApp/ContentView.swift`
- `iosApp/iosApp/Info.plist`
- `iosApp/iosApp/tvOS-Info.plist`

Tests:

- `iosApp/Tests/PairingProtocolTests.swift`
- `iosApp/Tests/PairingFrameTests.swift`

## 3. Wire Protocol

`PairingProtocol` defines:

- `PairingProtocol.version = 1`
- `PairingProtocol.serviceType = "_prairiepair._tcp"`

`PairingReceiverState` wire values:

- `setup`
- `login`

`PairingMessage` is a flat JSON object with:

- `type`
- `v`
- per-message fields at the top level

Message cases:

- `hello(tvName:tvDeviceId:state:supportedVersions:)`
- `pushServer(serverURL:serverName:)`
- `deviceStarted(serverURL:userCode:matchCode:)`
- `serverResult(serverURL:status:error:)`
- `done`
- `cancel(reason:)`

`PairingServerStatus` wire values:

- `signedIn`
- `failed`

Important compatibility detail: the JSON key is `serverURL`, with uppercase
`URL`, because Swift's coding key is `serverURL`.

## 4. Framing

`PairingFrame.encode(_:)` wraps every JSON payload with:

- 4-byte unsigned big-endian payload length
- payload bytes

`PairingFrame.maxFrameBytes` is `1 << 20`.

`PairingFrameBuffer.append(_:)` supports:

- partial reads,
- multiple frames in one read,
- oversized frame rejection.

This framing is dependency-free and tested by `PairingFrameTests.swift`.

## 5. Local Transport

`PairingSession` wraps a single `NWConnection`.

Constructors:

- `init(connection:)` for inbound tvOS receiver connections accepted by
  `NWListener`.
- `init(endpoint:)` for outbound iOS companion connections to a discovered TV.

Methods:

- `static func tlsParameters() -> NWParameters`
- `func open() -> AsyncThrowingStream<PairingMessage, Error>`
- `func send(_ message: PairingMessage) async throws`
- `func close()`

`tlsParameters()` configures:

- TLS over TCP.
- fixed PSK bytes: `prairie-companion-pairing-v1`
- fixed PSK identity: `prairie-pairing`
- cipher suite: `AES_128_GCM_SHA256`
- `includePeerToPeer = true`

The TLS configuration provides opportunistic confidentiality only. It is not an
authentication boundary because the PSK is compiled into the app. The
server-issued match code is the trust anchor.

## 6. Device Auth API Wrapper

`PairingDeviceAPI` is intentionally separate from the normal app API client
because companion pairing must call explicit server URLs without switching the
app's active server.

Receiver-side unauthenticated calls:

- `start(serverURL:deviceName:devicePlatform:)`
  - POST `{serverURL}/api/v1/auth/device/start`
  - body: `DeviceLoginStartRequest`
- `poll(serverURL:deviceCode:)`
  - POST `{serverURL}/api/v1/auth/device/poll`
  - body: `DeviceLoginPollRequest`

Companion-side authenticated calls:

- `lookup(serverURL:bearer:userCode:)`
  - GET `{serverURL}/api/v1/auth/device?code={userCode}`
  - bearer token from the chosen server
- `approve(serverURL:bearer:userCode:)`
  - POST `{serverURL}/api/v1/auth/device/approve`
  - body: `DeviceApproveRequest(code:)`

Every request includes:

- `X-Prairie-Device-Id`
- `X-Prairie-Device-Name`
- `X-Prairie-Device-Platform`

Authenticated calls include:

- `Authorization: Bearer <token>`

The API uses JSON snake-case encoding/decoding and ISO-8601 dates.

## 7. iOS Companion Discovery

`TVPairingBrowser` is iOS-only.

Method surface:

- `func start()`
- `func stop()`
- `private static func makeTV(_:) -> DiscoveredTV?`

It creates an `NWBrowser` for:

```swift
.bonjourWithTXTRecord(type: PairingProtocol.serviceType, domain: nil)
```

with `NWParameters.includePeerToPeer = true`.

Each result becomes:

```swift
DiscoveredTV(
    id: txt["id"] ?? "\(result.endpoint)",
    name: txt["name"] ?? "Apple TV",
    state: PairingReceiverState(rawValue: txt["st"] ?? "setup") ?? .setup,
    endpoint: result.endpoint
)
```

The browser publishes `found: [DiscoveredTV]`.

## 8. iOS Companion UI

`ContentView` mounts the pairing banner globally on iOS:

```swift
.setUpTVBanner()
```

`SetUpTVBannerModifier`:

- starts `TVPairingBrowser` in `.task`;
- picks the first discovered TV with `state == .setup`;
- ignores TVs dismissed by id;
- shows a top safe-area banner;
- opens `TVPairingView` as a sheet.

`TVPairingView`:

- constructs `PairingSession(endpoint: tv.endpoint)`;
- calls `session.open()`;
- creates `CompanionPairingCoordinator(session:stream:)`;
- calls `coordinator.begin()`;
- renders coordinator states:
  - `connecting`
  - `pickServers`
  - `confirmMatch`
  - `working`
  - `finished`
  - `error`

The server picker lets the user multi-select servers and calls
`coordinator.pushSelected(chosen)`.

The confirmation screen calls:

- `coordinator.confirmMatch()`
- `coordinator.declineMatch()`

Closing or disappearing calls `coordinator.cancel()`.

## 9. iOS Companion Coordinator

`CompanionPairingCoordinator` is `@MainActor` and `@Observable`.

Public methods:

- `begin()`
- `pushSelected(_:)`
- `confirmMatch()`
- `declineMatch()`
- `cancel()`

State cases:

- `connecting`
- `pickServers(tvName:servers:)`
- `confirmMatch(tvName:serverName:matchCode:)`
- `working(progress:)`
- `finished(signedIn:failed:)`
- `error(String)`

Flow:

1. `begin()` waits for `hello`.
2. It verifies `supportedVersions` contains `PairingProtocol.version`.
3. It loads `ServerRegistry.shared.sortedEntries`.
4. It filters to servers with a stored access token using
   `TokenStore.shared.getAccessToken(for:)`.
5. It presents `pickServers`.
6. `pushSelected(_:)` stores the selected server queue and starts `pushNext()`.
7. `pushNext()` sends `pushServer(serverURL:serverName:)`.
8. It waits for `deviceStarted`.
9. It fetches the server-authoritative match code via
   `PairingDeviceAPI.lookup(serverURL:bearer:userCode:)`.
10. The first server pauses in `confirmMatch`.
11. `confirmMatch()` marks the session confirmed and calls
    `approveAndAdvance(_:)`.
12. `approveAndAdvance(_:)` calls
    `PairingDeviceAPI.approve(serverURL:bearer:userCode:)`.
13. It waits for `serverResult`.
14. It records signed-in or failed server names.
15. It repeats until the queue is empty.
16. `finish()` sends `done`, closes the session, and reports summary state.

Security-critical behavior:

- The companion displays the match code returned by server lookup.
- It does not trust the `matchCode` copied over the LAN in `deviceStarted`.
- Only the first server in a multi-server session is visually confirmed; later
  servers are auto-approved after confirmation on the same session.

Stream-safety behavior:

- The coordinator serializes stream reads with `pump(_:)` and a single
  `AsyncIterator`, avoiding overlapping `AsyncThrowingStream` reads.

## 10. tvOS Receiver Advertising

`TVPairingAdvertiser` is tvOS-only.

Methods:

- `start(onConnection:)`
- `release()`
- `stop()`

`start(onConnection:)`:

1. Builds TXT record:
   - `v`
   - `name`
   - `id`
   - `st = setup`
2. Creates `NWListener(using: PairingSession.tlsParameters())`.
3. Sets `listener.service` to:

```swift
NWListener.Service(
    name: device.name,
    type: PairingProtocol.serviceType,
    txtRecord: txt
)
```

4. Accepts one connection at a time.
5. Wraps accepted `NWConnection` in `PairingSession(connection:)`.
6. Calls `session.open()`.
7. Passes `(session, stream)` to the receiver coordinator.

`release()` clears the `busy` flag after the coordinator exits.

## 11. tvOS Server Setup Integration

`TVServerSetupView` owns:

- `ServerSetupViewModel`
- `TVPairingAdvertiser`
- `ReceiverPairingCoordinator`

It starts advertising in `.task` via `startAdvertising()`.

On disappear it:

- stops the advertiser;
- cancels the coordinator.

The screen renders two modes:

- idle mode: `connectChooser`, with phone setup card and manual entry card;
- pairing mode: `TVPairingReceiverView(coordinator:router:)`.

`isPairing` is true for every receiver state except `.idle`, so the pairing
panel replaces the idle two-card layout in place.

## 12. tvOS Receiver UI

`TVPairingReceiverView` is presentation-only. It receives:

- `ReceiverPairingCoordinator`
- `AppRouter`

It renders:

- `linked`: phone connected, user is choosing servers on the phone.
- `awaitingApproval`: TV shows the match code and server name.
- `signedIn`: interim success while multi-server setup continues.
- `completed`: final success summary and `Continue`.
- `failed`: retry/fallback state.

`completed` auto-advances after a 1.8 second dwell, or immediately when the user
presses Continue.

Cancel/Try again calls `coordinator.cancel()`, returning the host screen to idle
while the advertiser remains available for another attempt.

## 13. tvOS Receiver Coordinator

`ReceiverPairingCoordinator` is `@MainActor` and `@Observable`.

Public methods:

- `run(session:stream:)`
- `cancel()`

State cases:

- `idle`
- `linked`
- `awaitingApproval(serverName:matchCode:)`
- `signedIn(serverCount:)`
- `completed(serverNames:)`
- `failed(String)`

Flow:

1. `run(session:stream:)` resets signed-in counters and stores `activeSession`.
2. It sends `hello(tvName:tvDeviceId:state:supportedVersions:)`.
3. It sets state to `linked`.
4. It continuously reads the session stream.
5. On `pushServer`, it starts `handlePushServer(serverURL:serverName:session:)`
   in a cancellable child `Task` and keeps reading the stream.
6. On `done`, it cancels in-flight polling if needed, waits for the task, sets
   `completed(serverNames:)` if at least one server signed in, and tears down
   without resetting state.
7. On `cancel`, stream end, or stream error, it tears down and resets to `idle`.

`handlePushServer(serverURL:serverName:session:)`:

1. Normalizes the pushed URL with `ServerRegistry.normalize(url:)`.
2. Treats the URL as a pending candidate.
3. Calls `PairingDeviceAPI.start(serverURL:deviceName:devicePlatform:)`.
4. Sets `awaitingApproval(serverName:matchCode:)`.
5. Sends `deviceStarted(serverURL:userCode:matchCode:)`.
6. Polls with `PairingDeviceAPI.poll(serverURL:deviceCode:)` until approval,
   denial, expiry, consumption, cancellation, or local timeout.
7. On `approved`, requires both access and refresh tokens.
8. Calls `persistOnSuccess(url:fetchedName:access:refresh:)`.
9. Updates signed-in counters and sends a `serverResult` message with
   `status == .signedIn`.
10. On terminal failure, sends a `serverResult` message with
    `status == .failed` and `error == "auth_failed"`.

`persistOnSuccess(url:fetchedName:access:refresh:)`:

1. Computes `ServerRegistry.serverId(for:)`.
2. Builds a `ServerEntry`.
3. Adds or updates the server in `ServerRegistry`.
4. Stores server URL in `TokenStore`.
5. Switches `TokenStore` active server.
6. Saves access and refresh tokens.
7. Switches `ServerRegistry` active server.

Persist-on-success is enforced: a pushed URL is not saved until the server poll
returns tokens.

## 14. Permissions And Configuration

iOS `Info.plist` includes:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` containing `_prairiepair._tcp`
- `NSAppTransportSecurity.NSAllowsLocalNetworking = true`

tvOS `tvOS-Info.plist` includes:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` containing `_prairiepair._tcp`
- `NSAppTransportSecurity.NSAllowsLocalNetworking = true`

## 15. Tests

`PairingProtocolTests.swift` is a standalone Swift test program. It verifies:

- every `PairingMessage` case round-trips through `JSONEncoder`/`JSONDecoder`;
- encoded messages include `type`;
- encoded messages include `v`;
- unknown `type` fails to decode.

`PairingFrameTests.swift` is a standalone Swift test program. It verifies:

- single-frame round trip;
- two frames in one chunk;
- one frame split across chunks;
- oversized length rejection.

These tests cover the pure wire-contract pieces. The network coordinators and UI
are not covered by XCTest in the current implementation.

## 16. Current Caveats

- The local socket transport currently depends on Apple `Network.framework`
  TLS-PSK behavior. Android interop needs either matching TLS-PSK support or a
  coordinated transport adjustment across both clients.
- The match-code confirmation is confirm-once per session. Multi-server
  follow-up approvals rely on the same already-confirmed session.
- The receiver stores only after successful polling, but it switches the active
  server to each newly persisted server as it succeeds. After multi-server
  pairing, the last successful server is active.
- The iOS banner picks the first non-dismissed discovered TV in `setup` state.
  It does not currently present a multi-TV chooser.
- `DeviceLookupResponse` only models the fields the current companion needs:
  `matchCode`, `deviceName`, `devicePlatform`, and `status`.
