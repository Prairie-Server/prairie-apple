# Android Cross-Platform Companion Pairing - Design Spec

- **Date:** 2026-06-14
- **Status:** Ready for engineering review
- **Primary implementation repo:** `silo-android`
- **Compatibility sources:** `silo-apple` companion pairing implementation and `silo-server` device-login endpoints
- **Related Apple spec:** `docs/superpowers/specs/2026-06-14-companion-pairing-design.md`

## 1. Goal

Replicate Silo companion pairing on Android with cross-platform compatibility:

- iPhone -> Apple TV already works and remains compatible.
- iPhone -> Android TV must work.
- Android phone -> Apple TV must work.
- Android phone -> Android TV must work.

The user experience stays the same across platforms: a signed-in phone discovers
a waiting TV on the same LAN, pushes one or more known server URLs, confirms the
server-issued match code, and approves the TV's Silo device login. The TV receives
tokens only from the Silo server over HTTPS.

This is client work. Do not add server endpoints for v1.

## 2. Non-goals

- Do not send access tokens, refresh tokens, passwords, profile tokens, or user
  credentials over the LAN pairing socket.
- Do not add a server-side device registry or cloud discovery.
- Do not add background phone wakeup or push-to-phone.
- Do not implement playback control or cast control in this spec.
- Do not replace the existing QR/device-code flow. It remains the fallback.

## 3. Existing Pieces To Reuse

### Apple implementation to match

The Apple implementation currently lives under `iosApp/iosApp/Pairing/`:

- `PairingProtocol.version`
- `PairingProtocol.serviceType`
- `PairingMessage`
- `PairingFrame.encode(_:)`
- `PairingFrameBuffer.append(_:)`
- `PairingSession.tlsParameters()`
- `PairingSession.open()`
- `PairingSession.send(_:)`
- `TVPairingAdvertiser.start(onConnection:)`
- `TVPairingBrowser.start()`
- `CompanionPairingCoordinator.begin()`
- `CompanionPairingCoordinator.pushSelected(_:)`
- `CompanionPairingCoordinator.confirmMatch()`
- `CompanionPairingCoordinator.declineMatch()`
- `ReceiverPairingCoordinator.run(session:stream:)`
- `PairingDeviceAPI.start(serverURL:deviceName:devicePlatform:)`
- `PairingDeviceAPI.poll(serverURL:deviceCode:)`
- `PairingDeviceAPI.lookup(serverURL:bearer:userCode:)`
- `PairingDeviceAPI.approve(serverURL:bearer:userCode:)`
- `TokenStore.getAccessToken(for:)`

Android must match the wire behavior of these methods, not just the product
concept.

### Android pieces already present

Use the existing Android auth and multi-server foundation:

- `DeviceLoginModels.kt`
  - `DeviceLoginStartRequest`
  - `DeviceLoginStartResponse`
  - `DeviceLoginPollRequest`
  - `DeviceLoginPollResponse`
  - `DeviceLoginLookupResponse`
  - `DeviceLoginDecisionRequest`
  - `DeviceLoginDecisionResponse`
  - `DeviceLoginStatus`
- `DeviceLoginApi.kt`
  - `startDeviceLogin`
  - `pollDeviceLogin`
  - `lookupDeviceLogin`
  - `approveDeviceLogin`
  - `denyDeviceLogin`
- `DeviceLoginRepository.kt`
  - `begin`
  - `lookup`
  - `approve`
  - `deny`
- `ServerRegistry`
  - `entries`
  - `activeServerId`
  - `activeEntry`
  - `addOrUpdate`
  - `switchTo`
  - `setProfileId`
- `AndroidServerRegistry`
  - `normalizeUrl`
  - `idFor`
  - `serverScopedKey`
- `TokenManager`
  - `getAccessToken`
  - `saveTokens`
  - `switchActiveServer`
- `EncryptedTokenManagerImpl`
  - per-server token persistence via encrypted `SharedPreferences`
- `TvLoginViewModel`
  - current Android TV QR/device-login token-save behavior
- `DevicePairingViewModel`
  - current Android phone approval screen for scanned QR/device-code flows

The LAN companion flow should reuse the data models and server endpoint shapes,
but it needs a new explicit-server API because pairing must call arbitrary server
URLs without switching the app's active server.

## 4. Compatibility Contract

### Protocol version

```
version = 1
```

Every LAN message must include:

```json
{ "type": "<message type>", "v": 1 }
```

Android decoders must reject unsupported `type` values and protocol versions
that are not in the negotiated supported-version set.

### Discovery

Service type:

```
_silopair._tcp
```

Apple currently uses `NWListener.Service(type: "_silopair._tcp")` and
`NWBrowser(for: .bonjourWithTXTRecord(type: "_silopair._tcp", domain: nil))`.
Android must use Android NSD/DNS-SD for the same service type.

TVs advertise. Phones browse.

TXT keys:

| Key | Required | Example | Meaning |
| --- | --- | --- | --- |
| `v` | yes | `1` | Pairing protocol version. |
| `name` | yes | `Living Room Shield` | User-facing TV name. |
| `id` | yes | stable device id | Stable TV id for de-dupe. |
| `st` | yes | `setup` | Receiver state. Use `setup` for v1; accept `login` as reserved. |

Receiver states:

```kotlin
enum class PairingReceiverState { Setup, Login }
```

Wire values:

- `setup`
- `login`

For current Apple compatibility, Android companions must work when Apple TV
advertises `setup`. Android receivers should advertise `setup` while waiting on
first-run/add-server/login screens. `login` is reserved; do not require it for
v1 interoperability.

### Transport and framing

Current Apple transport:

- Local TCP socket.
- Apple wraps the socket with TLS using `PairingSession.tlsParameters()`.
- Fixed non-secret PSK:
  - key bytes: UTF-8 `silo-companion-pairing-v1`
  - identity bytes: UTF-8 `silo-pairing`
- Apple appends cipher suite `AES_128_GCM_SHA256`.
- This TLS is opportunistic confidentiality, not authentication. The match code
  is the trust anchor.

Android implementation requirement:

1. First implement a transport compatibility spike against Apple:
   - Android companion connects to a tvOS receiver.
   - iOS companion connects to Android TV receiver.
   - Both sides exchange `hello` and `done`.
2. If Android's supported TLS stack can configure the same PSK parameters on
   minSdk 24, keep the Apple-compatible TLS-PSK transport.
3. If Android cannot reliably configure the same TLS-PSK transport, change both
   Apple and Android together to a plain local TCP transport using the same
   length-prefixed JSON framing. That is acceptable because tokens never cross
   the LAN and the match code remains mandatory. Do not ship an Android-only
   transport fork that cannot interoperate with Apple.

Regardless of TLS/plain socket, the application framing is identical:

- 4-byte unsigned big-endian length.
- Followed by that many UTF-8 JSON bytes.
- Maximum frame payload: `1 shl 20` bytes.
- Close the session on invalid length, invalid JSON, invalid type, or failed
  required-field validation.

Kotlin equivalent:

```kotlin
object PairingFrame {
    const val MAX_FRAME_BYTES = 1 shl 20

    fun encode(payload: ByteArray): ByteArray {
        require(payload.size <= MAX_FRAME_BYTES)
        return ByteBuffer.allocate(4 + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(payload.size)
            .put(payload)
            .array()
    }
}
```

The incremental decoder must support:

- one complete frame in one read,
- several frames in one read,
- one frame split across multiple reads,
- rejecting lengths larger than `MAX_FRAME_BYTES`.

## 5. Exact Wire Messages

Apple uses a flat JSON object, not a nested payload object. Android must emit the
same keys and casing. In particular, `serverURL` uses uppercase `URL`.

Use this DTO as the Kotlin serialization boundary:

```kotlin
@Serializable
data class PairingWireMessage(
    val type: String,
    val v: Int = PairingProtocol.VERSION,
    val tvName: String? = null,
    val tvDeviceId: String? = null,
    val state: String? = null,
    val supportedVersions: List<Int>? = null,
    @SerialName("serverURL") val serverUrl: String? = null,
    val serverName: String? = null,
    val userCode: String? = null,
    val matchCode: String? = null,
    val status: String? = null,
    val error: String? = null,
    val reason: String? = null,
)
```

Use a sealed domain model internally:

```kotlin
sealed interface PairingMessage {
    data class Hello(
        val tvName: String,
        val tvDeviceId: String,
        val state: PairingReceiverState,
        val supportedVersions: List<Int>,
    ) : PairingMessage

    data class PushServer(
        val serverUrl: String,
        val serverName: String?,
    ) : PairingMessage

    data class DeviceStarted(
        val serverUrl: String,
        val userCode: String,
        val matchCode: String,
    ) : PairingMessage

    data class ServerResult(
        val serverUrl: String,
        val status: PairingServerStatus,
        val error: String?,
    ) : PairingMessage

    data object Done : PairingMessage
    data class Cancel(val reason: String) : PairingMessage
}
```

Do not rely on kotlinx sealed-class polymorphic JSON output; it will not match
Swift's flat object. Always convert through `PairingWireMessage`.

Message table:

| Type | Direction | Required fields |
| --- | --- | --- |
| `hello` | TV -> phone | `tvName`, `tvDeviceId`, `state`, `supportedVersions` |
| `pushServer` | phone -> TV | `serverURL`; optional `serverName` |
| `deviceStarted` | TV -> phone | `serverURL`, `userCode`, `matchCode` |
| `serverResult` | TV -> phone | `serverURL`, `status`; optional `error` |
| `done` | phone -> TV | none beyond `type`, `v` |
| `cancel` | either | `reason` |

Status values:

```kotlin
enum class PairingServerStatus { SignedIn, Failed }
```

Wire values:

- `signedIn`
- `failed`

Canonical JSON fixtures:

```json
{"type":"hello","v":1,"tvName":"Living Room","tvDeviceId":"tv-123","state":"setup","supportedVersions":[1]}
{"type":"pushServer","v":1,"serverURL":"https://silo.example","serverName":"Home"}
{"type":"deviceStarted","v":1,"serverURL":"https://silo.example","userCode":"ABCD-1234","matchCode":"river-blue"}
{"type":"serverResult","v":1,"serverURL":"https://silo.example","status":"signedIn"}
{"type":"done","v":1}
{"type":"cancel","v":1,"reason":"user_cancelled"}
```

Encoding rules:

- Omit null optional fields.
- Use `Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }`.
- Validate required fields after decoding. Missing required fields are protocol
  errors and should close the session.
- Unknown extra fields should be ignored for forward compatibility.

## 6. Android File Layout

Use shared code for protocol and state machines where possible, with Android-only
files for NSD and socket/TLS transport.

Recommended new files:

```text
shared/src/commonMain/kotlin/com/continuum/app/pairing/
  PairingProtocol.kt
  PairingFrame.kt
  PairingSession.kt
  PairingDeviceApi.kt
  CompanionPairingCoordinator.kt
  ReceiverPairingCoordinator.kt

shared/src/androidMain/kotlin/com/continuum/app/pairing/
  AndroidPairingDiscovery.kt
  AndroidPairingAdvertiser.kt
  AndroidPairingSocketSession.kt
  AndroidPairingTransportFactory.kt

androidApp/src/androidMain/kotlin/com/continuum/app/android/ui/screens/pairing/
  SetUpTVBanner.kt
  TVPairingScreen.kt

androidTvApp/src/androidMain/kotlin/com/continuum/app/tv/ui/screens/pairing/
  TvPairingReceiverPanel.kt
```

Add Koin bindings in both app modules:

- phone app: browser/discovery, companion coordinator factory, phone UI screen
- TV app: advertiser/listener, receiver coordinator factory, TV panel

## 7. Android Discovery Methods

### TV advertiser

Implement an Android TV advertiser using `NsdManager.registerService`.

Method surface:

```kotlin
interface PairingAdvertiser {
    fun start(onConnection: suspend (PairingSession) -> Unit)
    fun release()
    fun stop()
}
```

Implementation behavior:

1. Open the local listening socket first so the port is known.
2. Create `NsdServiceInfo`:

```kotlin
val serviceInfo = NsdServiceInfo().apply {
    serviceName = deviceName
    serviceType = "_silopair._tcp."
    port = listeningPort
    setAttribute("v", "1")
    setAttribute("name", deviceName)
    setAttribute("id", stableDeviceId)
    setAttribute("st", "setup")
}
```

3. Register with `NsdManager.PROTOCOL_DNS_SD`.
4. Accept one connection at a time. Reject or close additional connections while
   `busy == true`.
5. Call `release()` after `ReceiverPairingCoordinator.run` exits so a new phone
   can retry.

Use the same stable device identity that Android already sends in Silo device
headers where possible. If there is no existing stable id helper, add one under
the shared Android device metadata provider and persist it.

### Phone browser

Implement a phone browser using `NsdManager.discoverServices`.

Method surface:

```kotlin
data class DiscoveredPairingTV(
    val id: String,
    val name: String,
    val state: PairingReceiverState,
    val host: InetAddress,
    val port: Int,
    val attributes: Map<String, String>,
)

interface PairingBrowser {
    val found: StateFlow<List<DiscoveredPairingTV>>
    fun start()
    fun stop()
}
```

Behavior:

1. Discover `_silopair._tcp.`.
2. Resolve services before surfacing them.
3. Parse TXT attributes:
   - `id` fallback: `"$host:$port"` if absent.
   - `name` fallback: `serviceName`.
   - `st` fallback: `setup`.
4. De-dupe by `id`.
5. Only browse while the app is foregrounded or while the explicit pairing screen
   is visible.
6. If discovery returns no TVs after about 10-15 seconds, show QR/manual fallback
   copy.

Recommended Android manifest additions for both phone and TV modules:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

Hold a `WifiManager.MulticastLock` while actively browsing/advertising if NSD
traffic is unreliable on real devices. Release it on stop.

## 8. Android PairingSession Methods

Keep a transport interface separate from the coordinator state machines.

```kotlin
interface PairingSession {
    suspend fun open(): Flow<PairingMessage>
    suspend fun send(message: PairingMessage)
    suspend fun close()
}
```

Implementation responsibilities:

- Serialize `send` calls with a mutex.
- Decode inbound frames sequentially on one coroutine.
- Finish the flow on clean EOF.
- Throw/close on malformed frames, malformed JSON, unsupported message type, or
  socket errors.
- Never expose raw socket bytes to coordinators.

Recommended Android implementation:

```kotlin
class AndroidPairingSocketSession(
    private val socket: Socket,
    private val json: Json = PairingJson,
) : PairingSession
```

If TLS-PSK compatibility is viable on Android, wrap the raw socket before
creating the session. If TLS-PSK compatibility is not viable, switch both Apple
and Android to plain local TCP in the same rollout and keep this session class as
the framing layer.

## 9. Explicit Device Login API

The existing `DefaultDeviceLoginApi` uses the app's configured Ktor client and
active server context. That is correct for QR login, but companion pairing needs
to talk to explicit server URLs from `PushServer` without disturbing the active
server.

Add a new API for pairing:

```kotlin
interface PairingDeviceApi {
    suspend fun start(
        serverUrl: String,
        deviceName: String?,
        devicePlatform: String?,
    ): ApiResult<DeviceLoginStartResponse>

    suspend fun poll(
        serverUrl: String,
        deviceCode: String,
    ): ApiResult<DeviceLoginPollResponse>

    suspend fun lookup(
        serverUrl: String,
        bearer: String,
        userCode: String,
    ): ApiResult<DeviceLoginLookupResponse>

    suspend fun approve(
        serverUrl: String,
        bearer: String,
        userCode: String,
    ): ApiResult<DeviceLoginDecisionResponse>
}
```

HTTP contract:

| Method | URL | Auth | Body/query |
| --- | --- | --- | --- |
| POST | `{serverUrl}/api/v1/auth/device/start` | none | `DeviceLoginStartRequest(device_name, device_platform)` |
| POST | `{serverUrl}/api/v1/auth/device/poll` | none | `DeviceLoginPollRequest(device_code)` |
| GET | `{serverUrl}/api/v1/auth/device?code={userCode}` | bearer allowed | no body |
| POST | `{serverUrl}/api/v1/auth/device/approve` | bearer required | `DeviceLoginDecisionRequest(code = userCode)` |

Implementation details:

- Use absolute URLs. Do not rely on the Ktor client's active-server base URL.
- Include `Authorization: Bearer <token>` for `lookup` and `approve`.
- Include the same Silo device metadata headers used by normal API calls:
  - `X-Silo-Device-Id`
  - `X-Silo-Device-Name`
  - `X-Silo-Device-Platform`
- Use the existing `DeviceLoginModels.kt` DTOs.
- Use `ApiResult` so coordinator tests can fake failures in the same style as
  `DeviceLoginRepositoryTest`.

## 10. TokenManager Gap

Apple companion approval uses `TokenStore.getAccessToken(for:)` so the phone can
approve a TV on a server that is not currently active.

Android needs the same capability.

Add this method to `TokenManager`:

```kotlin
suspend fun getAccessTokenForServer(serverId: String): String?
```

Implementation:

- `EncryptedTokenManagerImpl`: read
  `AndroidServerRegistry.serverScopedKey(serverId, KEY_ACCESS_TOKEN)` directly
  from encrypted prefs. If `serverId == activeServerId`, returning the cached
  active token is also fine.
- `TokenManagerImpl` common in-memory implementation: return the active token
  only when `serverId == getCurrentServerId()`, otherwise null.
- Update test fakes in Android unit tests.

Do not switch the phone's active server just to approve a companion request.

## 11. Companion Coordinator

The Android phone coordinator mirrors Apple's `CompanionPairingCoordinator`.

State:

```kotlin
sealed interface CompanionPairingState {
    data object Connecting : CompanionPairingState
    data class PickServers(val tvName: String, val servers: List<ServerEntry>) : CompanionPairingState
    data class ConfirmMatch(val tvName: String, val serverName: String, val matchCode: String) : CompanionPairingState
    data class Working(val progress: String) : CompanionPairingState
    data class Finished(val signedIn: List<String>, val failed: List<String>) : CompanionPairingState
    data class Error(val message: String) : CompanionPairingState
}
```

Methods:

```kotlin
class CompanionPairingCoordinator(
    private val session: PairingSession,
    private val api: PairingDeviceApi,
    private val serverRegistry: ServerRegistry,
    private val tokenManager: TokenManager,
) {
    val state: StateFlow<CompanionPairingState>

    suspend fun begin()
    suspend fun pushSelected(servers: List<ServerEntry>)
    suspend fun confirmMatch()
    suspend fun declineMatch()
    suspend fun cancel()
}
```

Exact behavior:

1. `begin`
   - Open/read the session.
   - Expect first relevant message to be `Hello`.
   - Check `hello.supportedVersions.contains(1)`.
   - Load `serverRegistry.entries.value`.
   - Filter to servers where `tokenManager.getAccessTokenForServer(server.id)`
     returns a non-blank token.
   - If none, show `Error("Sign in to a server on this phone first.")`.
   - Otherwise set `PickServers(tvName, servers)`.

2. `pushSelected`
   - Store the selected servers in order.
   - Process one server at a time.
   - Send `PushServer(server.url, server.displayName)`.
   - Wait for `DeviceStarted`; ignore unrelated messages; abort on `Cancel`.
   - Re-fetch authoritative match metadata:

```kotlin
val lookup = api.lookup(server.url, bearer = accessToken, userCode = started.userCode)
val serverMatchCode = lookup.data.matchCode.orEmpty()
```

   - Show the server-returned match code, not the `matchCode` copied over the
     LAN channel.
   - For the first server in the session, set
     `ConfirmMatch(tvName, server.displayName, serverMatchCode)`.
   - After the user confirms once, auto-approve remaining selected servers over
     the same session, matching Apple v1 behavior.

3. `confirmMatch`
   - Mark the session confirmed.
   - Call `api.approve(server.url, bearer = accessToken, userCode = pendingUserCode)`.
   - Wait for `ServerResult`.
   - If `status == signedIn`, append to `signedIn`; otherwise append to `failed`.
   - Advance the queue.

4. `declineMatch`
   - Send `Cancel("match_declined")`.
   - Close the session.
   - Set an error state.

5. `cancel`
   - Send `Cancel("user_cancelled")` best-effort.
   - Close the session.
   - Set an error/cancelled state.

6. Finish
   - Send `Done`.
   - Close the session.
   - Set `Finished(signedIn, failed)`.

Important security rule:

- Never approve using the channel-provided `matchCode`. Always call server
  lookup with the `userCode` and display the server's authoritative match code.

## 12. Receiver Coordinator

The Android TV coordinator mirrors Apple's `ReceiverPairingCoordinator`.

State:

```kotlin
sealed interface ReceiverPairingState {
    data object Idle : ReceiverPairingState
    data class AwaitingApproval(val serverName: String, val matchCode: String) : ReceiverPairingState
    data class SignedIn(val serverCount: Int) : ReceiverPairingState
    data class Failed(val serverName: String) : ReceiverPairingState
}
```

Methods:

```kotlin
class ReceiverPairingCoordinator(
    private val api: PairingDeviceApi,
    private val serverRegistry: ServerRegistry,
    private val tokenManager: TokenManager,
    private val deviceIdentity: DeviceIdentity,
    private val onAuthenticated: suspend () -> Unit,
) {
    val state: StateFlow<ReceiverPairingState>

    suspend fun run(session: PairingSession)
}
```

Exact behavior:

1. On run start, send:

```kotlin
PairingMessage.Hello(
    tvName = deviceIdentity.name,
    tvDeviceId = deviceIdentity.id,
    state = PairingReceiverState.Setup,
    supportedVersions = listOf(1),
)
```

2. Read the session stream continuously. Do not block stream reading inside the
   poll loop. Start/poll work for the current server must run in a cancellable
   child coroutine so `Cancel` or socket close aborts promptly.

3. On `PushServer(serverUrl, serverName)`:
   - If already polling, ignore or fail the overlapping request.
   - Normalize URL with `AndroidServerRegistry.normalizeUrl`.
   - Treat it as a pending candidate. Do not persist it yet.
   - Call:

```kotlin
api.start(
    serverUrl = normalized,
    deviceName = deviceIdentity.name,
    devicePlatform = "androidtv",
)
```

   - Set `AwaitingApproval(serverName ?: normalized, started.matchCode)`.
   - Send:

```kotlin
PairingMessage.DeviceStarted(
    serverUrl = normalized,
    userCode = started.userCode,
    matchCode = started.matchCode,
)
```

   - Poll until deadline:

```kotlin
api.poll(serverUrl = normalized, deviceCode = started.deviceCode)
```

   - Honor `pollAfter` if present; otherwise use `started.interval`, minimum 1s.

4. On approved poll response:
   - Require non-blank `accessToken` and `refreshToken`.
   - Persist only now:

```kotlin
val serverId = serverRegistry.addOrUpdate(normalized, fetchedName = serverName)
serverRegistry.switchTo(serverId)
tokenManager.saveTokens(
    accessToken = access,
    refreshToken = refresh,
    expiresIn = poll.expiresIn ?: 0L,
)
```

   - Increment signed-in count.
   - Set `SignedIn(count)`.
   - Send `ServerResult(normalized, SignedIn, null)`.

5. On denied, expired, consumed, timeout, network terminal failure, malformed
   response, or missing tokens:
   - Do not persist the pending candidate.
   - Set `Failed(serverName ?: normalized)`.
   - Send `ServerResult(normalized, Failed, "auth_failed")` best-effort.

6. On `Done`:
   - If a server is currently polling, cancel it. Do not persist partial state.
   - If at least one server signed in, call `onAuthenticated()`.
   - Close the session.

7. On `Cancel` or stream failure:
   - Cancel polling.
   - Discard pending candidate.
   - Close the session.
   - Return to idle/advertising.

Persist-on-success is mandatory. No URL or token state should survive a failed
pairing attempt.

## 13. UI Integration

### Android phone

Add a small discovery entry point:

- A banner or row equivalent to Apple `SetUpTVBanner`.
- Also add an explicit Settings entry: "Set up a TV".

Phone UI states:

1. Connecting to `{tv.name}`.
2. Server picker:
   - show `ServerRegistry.entries`
   - disable/hide servers without `getAccessTokenForServer`
   - allow multi-select
3. Match confirmation:
   - title: "Does your TV show this code?"
   - large uppercase match code
   - server display name
   - actions: "Doesn't match" and "Yes, set up"
4. Working progress.
5. Summary with signed-in and failed server names.

### Android TV

Add a panel alongside QR/manual login:

1. Idle:
   - "Set up with phone"
   - "Open Silo on your phone on the same Wi-Fi."
2. Awaiting approval:
   - "Confirm on your phone"
   - large match code
   - server name
3. Signed in:
   - "Signed in" or "Signed in to N servers"
4. Failed:
   - show fallback to QR/manual

Keep the existing QR panel active as a fallback.

## 14. Server API Details

The server implementation already exposes:

- `HandleDeviceStart`
- `HandleDeviceLookup`
- `HandleDevicePoll`
- `HandleDeviceApprove`
- `HandleDeviceDeny`

Routes:

```text
POST /api/v1/auth/device/start
GET  /api/v1/auth/device?code=<userCode>
GET  /api/v1/auth/device?token=<browserCode>
POST /api/v1/auth/device/poll
POST /api/v1/auth/device/approve
POST /api/v1/auth/device/deny
```

Response/status behavior:

- `start` creates a pending request with 10-minute TTL and returns
  `device_code`, `user_code`, `match_code`, `verification_uri`,
  `verification_uri_complete`, `expires_at`, `expires_in`, `interval`,
  `device_name`, `device_platform`.
- `poll` returns `pending`, `approved`, `denied`, `expired`, or `consumed`.
- On first `approved` poll, server returns `access_token`, `refresh_token`,
  `expires_in`, and `user`, then consumes the device request.
- `approve` is authenticated and uses `DeviceLoginDecisionRequest(code = userCode)`.
- `lookup` is public but Android should send bearer when available to mirror
  Apple and to keep future authorization changes compatible.

## 15. Security Model

- LAN channel carries server URLs, user codes, match codes, and statuses only.
- Tokens are delivered only to the TV over HTTPS from `/device/poll`.
- The local channel's confidentiality is best-effort. It must not be the trust
  boundary.
- The match code is the trust boundary:
  - TV gets `matchCode` from the real server over HTTPS.
  - Phone gets authoritative `matchCode` by calling server lookup with `userCode`.
  - User confirms both screens show the same code before approval.
- Android must keep the Apple v1 confirm-once policy for compatibility:
  - first selected server requires visual confirmation;
  - later selected servers in the same socket session are auto-approved.
- The confirm-once multi-server risk from the Apple spec is accepted for v1.
  If we later raise the threat model, change both platforms to confirm per
  server or add authenticated key agreement.

## 16. Testing Requirements

### Shared unit tests

Add common tests for:

- `PairingWireMessage` encode/decode for every message type.
- Exact JSON fixtures listed in this spec.
- Unknown `type` fails.
- Unsupported version fails negotiation.
- Missing required fields fail conversion to domain model.
- `PairingFrame`:
  - single frame round-trip,
  - two frames in one chunk,
  - split frame,
  - oversized length rejection.

### Coordinator tests

Use fake `PairingSession` and fake `PairingDeviceApi`.

Companion tests:

- happy path, one server;
- happy path, multiple servers with confirm once;
- no signed-in servers;
- unsupported version;
- lookup returns different match code than channel and coordinator displays
  server lookup value;
- decline sends `Cancel("match_declined")`;
- failed `ServerResult` continues remaining servers;
- dropped session fails without approving.

Receiver tests:

- sends `Hello` first;
- `PushServer` starts device login and emits `DeviceStarted`;
- approved poll persists server and tokens only after approval;
- denied/expired/consumed/missing-tokens persist nothing;
- `Cancel` during poll cancels work and persists nothing;
- `Done` after at least one success calls `onAuthenticated`;
- overlapping `PushServer` while polling is ignored or failed consistently.

### Android instrumentation/manual tests

Manual interop matrix:

| Companion | Receiver | Expected |
| --- | --- | --- |
| iOS | tvOS | existing flow remains green |
| iOS | Android TV | discover, connect, confirm, approve, TV reaches profile selection |
| Android phone | tvOS | discover, connect, confirm, approve, TV reaches profile selection |
| Android phone | Android TV | discover, connect, confirm, approve, TV reaches profile selection |

Network conditions:

- same Wi-Fi;
- AP/client isolation enabled (should fall back);
- Local Network/NSD unavailable (fallback);
- TV app backgrounded (not discoverable for v1);
- phone app backgrounded (browser stops);
- match code declined;
- one selected server fails and another succeeds.

## 17. Implementation Order

1. Add protocol/framing common code and tests.
2. Add explicit-server `PairingDeviceApi`.
3. Add `TokenManager.getAccessTokenForServer`.
4. Implement Android socket transport and Apple interop spike.
5. Implement Android NSD browser/advertiser.
6. Implement receiver coordinator with fake tests.
7. Implement companion coordinator with fake tests.
8. Wire Android TV pairing panel.
9. Wire Android phone discovery banner/settings flow.
10. Run the full four-direction interop matrix.

Do not wire UI before the protocol/framing/coordinator tests exist. Most failure
modes are state-machine bugs, not Compose bugs.

## 18. Acceptance Criteria

- Android protocol tests pass against the exact JSON fixtures in this spec.
- Android frame tests match Apple `PairingFrame` behavior.
- Android receiver persists no server/token state until approved poll returns
  tokens.
- Android companion displays the match code from server lookup, not from the LAN
  message.
- iOS can set up Android TV.
- Android phone can set up tvOS.
- Android phone can set up Android TV.
- Existing iOS -> tvOS pairing still works.
- QR/manual device login still works on both Android phone and Android TV.
