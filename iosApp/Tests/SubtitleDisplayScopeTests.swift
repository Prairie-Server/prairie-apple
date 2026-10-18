import XCTest
@testable import Prairie

/// Where subtitle display edits are saved (prairie-server#1157): appearance and
/// timing follow the profile to every device, unless this device keeps its own
/// through the "Only on This Device" override.
@MainActor
final class SubtitleDisplayScopeTests: XCTestCase {

    private func appearanceRow(_ value: SettingJSONValue, at scope: SettingScope) -> EffectiveSettingValue {
        EffectiveSettingValue(
            key: SettingKey.playbackSubtitleAppearance.rawValue,
            value: value,
            source: .scope(scope),
            scope: scope
        )
    }

    private func syncRow(_ milliseconds: Int, at scope: SettingScope) -> EffectiveSettingValue {
        EffectiveSettingValue(
            key: SettingKey.playerSubtitleSyncMs.rawValue,
            value: .int(milliseconds),
            source: .scope(scope),
            scope: scope
        )
    }

    // MARK: - Appearance

    func testAnAppearanceEditIsSavedForTheProfile() async throws {
        let harness = try PlayerSettingsHarness()
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        var appearance = SubtitleAppearance.default
        appearance.fontSize = .xlarge
        await harness.settings.setSubtitleAppearance(appearance)

        let write = try XCTUnwrap(harness.transport.writesByKey()[.playbackSubtitleAppearance])
        XCTAssertEqual(write.scope, .profile)
        XCTAssertEqual(write.value, try SettingJSONValue.encoding(appearance.sanitized()))
        // Sent even with no device value known: the flusher treats "nothing
        // to delete" as success.
        XCTAssertEqual(
            harness.transport.scopedDeletes(),
            [.init(key: .playbackSubtitleAppearance, scope: .profileDevice)]
        )
        XCTAssertFalse(harness.settings.subtitleUsesDeviceAppearanceOverride)
        XCTAssertEqual(harness.settings.effectiveSubtitleAppearance.fontSize, .xlarge)

        // The next read still has the old profile value while the write is
        // owed elsewhere; once it lands it is the profile's, not this device's.
        harness.transport.effective = [
            appearanceRow(try SettingJSONValue.encoding(appearance.sanitized()), at: .profile),
        ]
        await harness.settings.refreshFromServer()
        XCTAssertFalse(harness.settings.subtitleUsesDeviceAppearanceOverride)
        XCTAssertEqual(harness.settings.subtitleAppearance.fontSize, .xlarge)
    }

    func testAnAppearanceEditWhileTheDeviceKeepsItsOwnStaysOnThisDevice() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [appearanceRow(["fontSize": "small"], at: .profileDevice)]
        await harness.settings.refreshFromServer()
        XCTAssertTrue(harness.settings.subtitleUsesDeviceAppearanceOverride)
        harness.transport.reset()

        var next = harness.settings.subtitleAppearance
        next.position = .top
        await harness.settings.setSubtitleAppearance(next)

        let write = try XCTUnwrap(harness.transport.writesByKey()[.playbackSubtitleAppearance])
        XCTAssertEqual(write.scope, .profileDevice)
        XCTAssertEqual(write.value.objectValue?["fontSize"], .string("small"))
        XCTAssertEqual(write.value.objectValue?["position"], .string("top"))
        XCTAssertTrue(harness.settings.subtitleUsesDeviceAppearanceOverride)
    }

    /// The in-player controls mutate `subtitleAppearance`. That must be what is
    /// on screen (the profile's appearance), not a device copy an earlier
    /// override left in the cache, or the first in-player edit would replace
    /// the profile's style with stale values.
    func testAnEditStartsFromTheAppearanceOnScreenNotAStaleDeviceCopy() async throws {
        let harness = try PlayerSettingsHarness()
        var stale = SubtitleAppearance.default
        stale.fontSize = .small
        stale.fontColor = "#facc15"
        harness.defaults.set(stale.jsonString, forKey: "player.subtitleAppearance")
        harness.transport.effective = [appearanceRow(["fontSize": "xxlarge"], at: .profile)]
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        XCTAssertEqual(harness.settings.subtitleAppearance.fontSize, .xxlarge)
        XCTAssertEqual(harness.settings.subtitleAppearance, harness.settings.effectiveSubtitleAppearance)

        var next = harness.settings.subtitleAppearance
        next.position = .top
        harness.settings.stageSubtitleAppearance(next)
        await harness.settings.flushPendingDeviceSettings()

        let fields = try XCTUnwrap(harness.transport.writesByKey()[.playbackSubtitleAppearance]?.value.objectValue)
        XCTAssertEqual(fields["fontSize"], .string("xxlarge"))
        XCTAssertEqual(
            fields["fontColor"],
            try SettingJSONValue.encoding(SubtitleAppearance.default.sanitized()).objectValue?["fontColor"]
        )
        XCTAssertEqual(fields["position"], .string("top"))
    }

    func testTurningTheDeviceOverrideOnKeepsTheAppearanceOnScreen() async throws {
        let harness = try PlayerSettingsHarness()
        var stale = SubtitleAppearance.default
        stale.fontSize = .small
        harness.defaults.set(stale.jsonString, forKey: "player.subtitleAppearance")
        harness.transport.effective = [appearanceRow(["fontSize": "xlarge"], at: .profile)]
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        await harness.settings.setSubtitleDeviceOverrideEnabled(true)

        XCTAssertTrue(harness.settings.subtitleUsesDeviceAppearanceOverride)
        XCTAssertEqual(harness.settings.effectiveSubtitleAppearance.fontSize, .xlarge)
        let write = try XCTUnwrap(harness.transport.writesByKey()[.playbackSubtitleAppearance])
        XCTAssertEqual(write.scope, .profileDevice)
        XCTAssertEqual(write.value.objectValue?["fontSize"], .string("xlarge"))
    }

    /// An appearance edit that has not reached the profile yet (here: the
    /// server was unreachable) still goes to the profile when the device
    /// override is turned on before it is sent.
    func testTurningTheOverrideOnKeepsAnUnsentProfileEdit() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [appearanceRow(["fontSize": "small"], at: .profile)]
        await harness.settings.refreshFromServer()
        harness.transport.reset()
        harness.transport.failNextWrites(1, with: .transport(description: "offline"))

        var appearance = harness.settings.subtitleAppearance
        appearance.fontSize = .xlarge
        await harness.settings.setSubtitleAppearance(appearance)
        await harness.settings.setSubtitleDeviceOverrideEnabled(true)

        let expected = try SettingJSONValue.encoding(appearance.sanitized())
        let writes = harness.transport.writes()
        XCTAssertEqual(writes.last { $0.scope == .profile }?.value, expected, "the profile still gets the edit")
        XCTAssertEqual(writes.last?.scope, .profileDevice)
        XCTAssertEqual(writes.last?.value, expected)
        XCTAssertTrue(harness.settings.subtitleUsesDeviceAppearanceOverride)
    }

    func testTurningTheDeviceOverrideOffDeletesThisDevicesAppearanceAndOffset() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [
            appearanceRow(["fontSize": "small"], at: .profileDevice),
            syncRow(400, at: .profileDevice),
        ]
        await harness.settings.refreshFromServer()
        harness.transport.reset()
        harness.transport.effective = [
            appearanceRow(["fontSize": "large"], at: .profile),
            syncRow(-250, at: .profile),
        ]

        await harness.settings.setSubtitleDeviceOverrideEnabled(false)

        XCTAssertEqual(
            Set(harness.transport.scopedDeletes().map { "\($0.key.rawValue)@\($0.scope.rawValue)" }),
            [
                "playback.subtitle_appearance@profile_device",
                "player.subtitle_sync_ms@profile_device",
            ]
        )
        XCTAssertTrue(harness.transport.writes().isEmpty)
        XCTAssertFalse(harness.settings.subtitleUsesDeviceAppearanceOverride)
        XCTAssertEqual(harness.settings.subtitleAppearance.fontSize, .large)
        XCTAssertEqual(harness.settings.subtitleSyncMs, -250)
    }

    /// The offset clear does not depend on this device having seen its own
    /// offset: after a reinstall, or before a refresh, it may not have.
    func testTurningTheOverrideOffClearsADeviceOffsetThisDeviceHadNotSeen() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [appearanceRow(["fontSize": "small"], at: .profileDevice)]
        await harness.settings.refreshFromServer()
        XCTAssertFalse(harness.settings.deviceOverriddenKeys.contains(.playerSubtitleSyncMs))
        harness.transport.reset()

        await harness.settings.setSubtitleDeviceOverrideEnabled(false)

        XCTAssertEqual(Set(harness.transport.deletes()), [.playbackSubtitleAppearance, .playerSubtitleSyncMs])
    }

    /// While the clear is still owed the server answers with the device value
    /// it removes. The override stays off, and the next edit goes to the
    /// profile.
    func testTheOverrideStaysOffWhileItsClearIsStillOwed() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [appearanceRow(["fontSize": "small"], at: .profileDevice)]
        await harness.settings.refreshFromServer()
        harness.transport.reset()
        harness.transport.failNextDeletes(100, with: .transport(description: "offline"))

        await harness.settings.setSubtitleDeviceOverrideEnabled(false)
        XCTAssertFalse(harness.settings.subtitleUsesDeviceAppearanceOverride)

        var next = harness.settings.subtitleAppearance
        next.position = .top
        await harness.settings.setSubtitleAppearance(next)
        XCTAssertEqual(harness.transport.writesByKey()[.playbackSubtitleAppearance]?.scope, .profile)
    }

    func testTurningTheOverrideOffKeepsTheDeviceOffsetOnAServerWithoutAProfileOffset() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        harness.transport.effective = [
            appearanceRow(["fontSize": "small"], at: .profileDevice),
            syncRow(400, at: .profileDevice),
        ]
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        await harness.settings.setSubtitleDeviceOverrideEnabled(false)

        XCTAssertEqual(harness.transport.deletes(), [.playbackSubtitleAppearance])
    }

    /// A launch that has not reached the server yet does not know whether
    /// the profile can hold an offset. Turning the override off then still
    /// owes the offset clear, decided once a read reports the revision.
    func testTurningTheOverrideOffBeforeTheRevisionIsKnownClearsTheOffsetOnACurrentServer() async throws {
        let (settings, transport) = try await offlineLaunchWithDeviceOffset()

        await settings.setSubtitleDeviceOverrideEnabled(false)
        XCTAssertEqual(transport.deletes(), [.playbackSubtitleAppearance])

        transport.effectiveError = nil
        await settings.refreshFromServer()
        XCTAssertEqual(
            transport.scopedDeletes(),
            [
                .init(key: .playbackSubtitleAppearance, scope: .profileDevice),
                .init(key: .playerSubtitleSyncMs, scope: .profileDevice),
            ]
        )
    }

    func testTurningTheOverrideOffBeforeTheRevisionIsKnownKeepsTheOffsetOnAnOlderServer() async throws {
        let (settings, transport) = try await offlineLaunchWithDeviceOffset()

        await settings.setSubtitleDeviceOverrideEnabled(false)

        transport.effectiveError = nil
        transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        transport.effective = [syncRow(400, at: .profileDevice)]
        await settings.refreshFromServer()
        XCTAssertEqual(transport.deletes(), [.playbackSubtitleAppearance])
        XCTAssertTrue(settings.deviceOverriddenKeys.contains(.playerSubtitleSyncMs))

        // Settled, not left waiting to be sent later.
        transport.revision = SettingKey.revision
        await settings.refreshFromServer()
        XCTAssertEqual(transport.deletes(), [.playbackSubtitleAppearance])
    }

    /// An offset edited offline while the device keeps its own, then the
    /// override turned off: on a server that only stores offsets per device
    /// the clear does not apply, and the edit must still be saved.
    func testAnUnsentDeviceOffsetSurvivesTheOverrideTurningOffOnAnOlderServer() async throws {
        let (settings, transport) = try await offlineLaunchWithDeviceOffset()

        transport.failNextWrites(100, with: .transport(description: "offline"))
        transport.failNextDeletes(100, with: .transport(description: "offline"))
        settings.setSubtitleSyncMs(-700)
        await settings.setSubtitleDeviceOverrideEnabled(false)

        transport.succeedFromNowOn()
        transport.reset()
        transport.effectiveError = nil
        transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        transport.effective = [syncRow(400, at: .profileDevice)]
        await settings.refreshFromServer()

        XCTAssertEqual(
            transport.writesByKey()[.playerSubtitleSyncMs],
            .init(key: .playerSubtitleSyncMs, value: .int(-700), profileId: nil, scope: .profileDevice)
        )
        XCTAssertEqual(transport.deletes(), [.playbackSubtitleAppearance])
        XCTAssertEqual(settings.subtitleSyncMs, -700)
    }

    /// Settings whose cache holds a device appearance and offset from an
    /// earlier run, launched while the server is unreachable.
    private func offlineLaunchWithDeviceOffset() async throws -> (PlayerSettings, FakeSettingsTransport) {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [
            appearanceRow(["fontSize": "small"], at: .profileDevice),
            syncRow(400, at: .profileDevice),
        ]
        await harness.settings.refreshFromServer()
        XCTAssertTrue(harness.settings.deviceOverriddenKeys.contains(.playerSubtitleSyncMs))

        let transport = FakeSettingsTransport()
        transport.effectiveError = .transport(description: "offline")
        let settings = PlayerSettings(
            defaults: harness.defaults,
            flusher: PlayerSettingsFlusher(transport: transport, debounce: .milliseconds(10))
        )
        addTeardownBlock { _ = harness }
        await settings.refreshFromServer()
        XCTAssertNil(settings.knownManifestRevision)
        XCTAssertTrue(settings.subtitleUsesDeviceAppearanceOverride)
        return (settings, transport)
    }

    // MARK: - Timing

    /// Older builds saved every Delay change as this device's own offset
    /// without turning the override on. On a server that stores the offset per
    /// profile that leftover is cleared once, a failed clear is retried, and an
    /// offset the device holds later is left alone.
    func testALeftoverDeviceOffsetIsClearedOnceOnACurrentServer() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [syncRow(400, at: .profileDevice)]
        harness.transport.failNextDeletes(1, with: .transport(description: "offline"))
        await harness.settings.refreshFromServer()
        XCTAssertFalse(harness.settings.subtitleUsesDeviceAppearanceOverride)
        XCTAssertEqual(harness.transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])

        harness.transport.reset()
        harness.transport.effective = [syncRow(-250, at: .profile)]
        await harness.settings.refreshFromServer()
        XCTAssertEqual(harness.transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])
        XCTAssertEqual(harness.settings.subtitleSyncMs, -250)
        XCTAssertFalse(harness.settings.deviceOverriddenKeys.contains(.playerSubtitleSyncMs))

        harness.transport.reset()
        harness.transport.effective = [syncRow(300, at: .profileDevice)]
        await harness.settings.refreshFromServer()
        XCTAssertTrue(harness.transport.deletes().isEmpty)
        XCTAssertEqual(harness.settings.subtitleSyncMs, 300)
    }

    /// A failed clear retried after a relaunch waits for the server's
    /// revision, and a server rolled back below revision 19 keeps the offset.
    func testALeftoverOffsetClearRetriedAfterARelaunchSparesAnOlderServer() async throws {
        let harness = try PlayerSettingsHarness()
        let journal = InMemoryWriteJournal()
        let first = FakeSettingsTransport()
        first.effective = [syncRow(400, at: .profileDevice)]
        first.failNextDeletes(1, with: .transport(description: "offline"))
        let settings = PlayerSettings(
            defaults: harness.defaults,
            flusher: PlayerSettingsFlusher(transport: first, debounce: .milliseconds(10), journal: journal)
        )
        await settings.refreshFromServer()
        XCTAssertEqual(first.deletes(), [.playerSubtitleSyncMs])

        let relaunch = FakeSettingsTransport()
        relaunch.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        relaunch.effective = [syncRow(400, at: .profileDevice)]
        let relaunched = PlayerSettings(
            defaults: harness.defaults,
            flusher: PlayerSettingsFlusher(transport: relaunch, debounce: .milliseconds(10), journal: journal)
        )
        await relaunched.refreshFromServer()
        XCTAssertTrue(relaunch.deletes().isEmpty)
        XCTAssertEqual(relaunched.subtitleSyncMs, 400)
    }

    /// An older build's device offset still owed when a current server is
    /// first read lands later; the one-time clear waits for it.
    func testALeftoverOffsetStillOwedIsClearedOnceItLands() async throws {
        let harness = try PlayerSettingsHarness()
        let journal = InMemoryWriteJournal()
        journal.stored = [
            .playerSubtitleSyncMs: PendingSettingWrite(operation: .set(.int(400)), scope: .profileDevice),
        ]
        let transport = FakeSettingsTransport()
        transport.failNextWrites(1, with: .transport(description: "offline"))
        transport.effective = [syncRow(400, at: .profileDevice)]
        let settings = PlayerSettings(
            defaults: harness.defaults,
            flusher: PlayerSettingsFlusher(transport: transport, debounce: .milliseconds(10), journal: journal)
        )
        await settings.refreshFromServer()
        XCTAssertTrue(transport.deletes().isEmpty)

        await settings.refreshFromServer()
        XCTAssertEqual(transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])
    }

    func testALeftoverDeviceOffsetIsClearedAndRepaintedInOneRefresh() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [syncRow(400, at: .profileDevice)]
        // The server answers with the profile's offset once the clear lands.
        let profileRow = syncRow(-250, at: .profile)
        harness.transport.onDelete = { [transport = harness.transport] _ in
            transport.effective = [profileRow]
        }
        await harness.settings.refreshFromServer()
        XCTAssertEqual(harness.transport.deletes(), [.playerSubtitleSyncMs])
        XCTAssertEqual(harness.settings.subtitleSyncMs, -250)
    }

    /// A device that keeps its own subtitle settings chose its offset.
    func testADeviceOffsetIsKeptWhileTheOverrideIsOn() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [
            appearanceRow(["fontSize": "small"], at: .profileDevice),
            syncRow(400, at: .profileDevice),
        ]
        await harness.settings.refreshFromServer()
        XCTAssertTrue(harness.transport.deletes().isEmpty)
        XCTAssertEqual(harness.settings.subtitleSyncMs, 400)
    }

    func testALeftoverDeviceOffsetIsKeptOnAnOlderServer() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        harness.transport.effective = [syncRow(400, at: .profileDevice)]
        await harness.settings.refreshFromServer()
        XCTAssertTrue(harness.transport.deletes().isEmpty)
        XCTAssertEqual(harness.settings.subtitleSyncMs, 400)
    }

    func testASubtitleOffsetIsSavedForTheProfileOnACurrentServer() async throws {
        let harness = try PlayerSettingsHarness()
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        harness.settings.setSubtitleSyncMs(-500)
        await harness.settings.flushPendingDeviceSettings()

        XCTAssertEqual(
            harness.transport.writes(),
            [.init(key: .playerSubtitleSyncMs, value: .int(-500), profileId: nil, scope: .profile)]
        )
        XCTAssertEqual(harness.transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])
    }

    /// The profile offset is stored but the clear of the older device offset
    /// keeps failing. A refresh meanwhile still answers with the device
    /// offset; the offset just saved stays in effect here.
    func testAStoredProfileOffsetStaysInEffectWhileTheDeviceClearIsOwed() async throws {
        let harness = try PlayerSettingsHarness()
        await harness.settings.refreshFromServer()
        harness.transport.reset()
        harness.transport.failNextDeletes(100, with: .transport(description: "offline"))

        harness.settings.setSubtitleSyncMs(-500)
        await harness.settings.flushPendingDeviceSettings()
        harness.transport.effective = [syncRow(400, at: .profileDevice)]
        await harness.settings.refreshFromServer()

        XCTAssertEqual(harness.transport.writes().map(\.scope), [.profile])
        XCTAssertEqual(harness.settings.subtitleSyncMs, -500)
        XCTAssertFalse(harness.settings.deviceOverriddenKeys.contains(.playerSubtitleSyncMs))
    }

    func testASubtitleOffsetStaysOnThisDeviceWhileTheDeviceKeepsItsOwn() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [appearanceRow(["fontSize": "small"], at: .profileDevice)]
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        harness.settings.setSubtitleSyncMs(300)
        await harness.settings.flushPendingDeviceSettings()

        XCTAssertEqual(harness.transport.writesByKey()[.playerSubtitleSyncMs]?.scope, .profileDevice)
    }

    func testASubtitleOffsetStaysADeviceValueOnAServerBeforeRevision18() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        harness.settings.setSubtitleSyncMs(-500)
        await harness.settings.flushPendingDeviceSettings()

        XCTAssertEqual(harness.transport.writesByKey()[.playerSubtitleSyncMs]?.scope, .profileDevice)
        XCTAssertTrue(harness.transport.deletes().isEmpty)
    }

    /// An older build saved every offset on the device. That value would keep
    /// hiding the profile's offset here, so a profile save deletes it.
    func testAProfileSaveDeletesAnOffsetAnOlderBuildLeftOnThisDevice() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effective = [
            appearanceRow(["fontSize": "large"], at: .profile),
            syncRow(900, at: .profileDevice),
        ]
        await harness.settings.refreshFromServer()
        harness.transport.reset()

        harness.settings.setSubtitleSyncMs(-500)
        await harness.settings.flushPendingDeviceSettings()

        XCTAssertEqual(harness.transport.writesByKey()[.playerSubtitleSyncMs]?.scope, .profile)
        XCTAssertEqual(
            harness.transport.scopedDeletes(),
            [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)]
        )
    }

    /// While the revision is unknown the write waits; it then goes to the
    /// scope that server accepts.
    func testAnOffsetMadeBeforeTheRevisionIsKnownWaitsAndFallsBackOnAnOlderServer() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effectiveError = .transport(description: "offline")
        await harness.settings.refreshFromServer()
        XCTAssertNil(harness.settings.knownManifestRevision)

        harness.settings.setSubtitleSyncMs(-500)
        await harness.settings.flushPendingDeviceSettings()
        XCTAssertTrue(harness.transport.writes().isEmpty, "must not guess the server's revision")

        harness.transport.effectiveError = nil
        harness.transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        await harness.settings.refreshFromServer()

        let write = try XCTUnwrap(harness.transport.writesByKey()[.playerSubtitleSyncMs])
        XCTAssertEqual(write.scope, .profileDevice)
        XCTAssertEqual(write.value, .int(-500))
        XCTAssertEqual(harness.settings.subtitleSyncMs, -500)
    }

    func testAnOffsetMadeBeforeTheRevisionIsKnownGoesToTheProfileOnACurrentServer() async throws {
        let harness = try PlayerSettingsHarness()
        harness.transport.effectiveError = .transport(description: "offline")
        await harness.settings.refreshFromServer()

        harness.settings.setSubtitleSyncMs(250)
        await harness.settings.flushPendingDeviceSettings()
        XCTAssertTrue(harness.transport.writes().isEmpty)

        harness.transport.effectiveError = nil
        await harness.settings.refreshFromServer()

        XCTAssertEqual(harness.transport.writesByKey()[.playerSubtitleSyncMs]?.scope, .profile)
        // No refresh had shown a device offset, but one may be on the server
        // already, and it would keep hiding the profile offset here.
        XCTAssertEqual(harness.transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])
    }

    // MARK: - Queue

    /// A second edit inside the debounce window must keep the device clear the
    /// first one owed, or the old device value would survive.
    func testANewerProfileWriteKeepsAnOwedDeviceClear() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])

        flusher.enqueue(.playerSubtitleSyncMs, value: .int(100), scope: .profile, clearingDeviceValue: true)
        flusher.enqueue(.playerSubtitleSyncMs, value: .int(200), scope: .profile)
        await flusher.flushNow()

        XCTAssertEqual(transport.writes().map(\.value), [.int(200)])
        XCTAssertEqual(transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])
    }

    /// Turning the override off queues a clear; a profile edit before it is
    /// sent must still clear the device value.
    func testAProfileWriteReplacingAQueuedDeviceClearStillClears() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])

        flusher.enqueueDelete(.playbackSubtitleAppearance)
        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile)
        await flusher.flushNow()

        XCTAssertEqual(transport.writes().map(\.scope), [.profile])
        XCTAssertEqual(
            transport.scopedDeletes(),
            [.init(key: .playbackSubtitleAppearance, scope: .profileDevice)]
        )
    }

    /// Turning the override off starts a clear; a profile edit made while it
    /// is being sent must still clear the device value if that send fails.
    func testAProfileWriteQueuedDuringAFailingDeviceClearStillClears() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        transport.failNextDeletes(1, with: .transport(description: "offline"))
        transport.onDelete = { [weak flusher] _ in
            transport.onDelete = nil
            flusher?.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile)
        }

        flusher.enqueueDelete(.playbackSubtitleAppearance)
        await flusher.flushNow()

        XCTAssertFalse(flusher.hasPendingWrites)
        XCTAssertEqual(transport.writes().map(\.scope), [.profile])
        XCTAssertEqual(
            transport.scopedDeletes(),
            [
                .init(key: .playbackSubtitleAppearance, scope: .profileDevice),
                .init(key: .playbackSubtitleAppearance, scope: .profileDevice),
            ],
            "the failed clear is sent again with the profile write"
        )
    }

    /// The device clear is a second request. A profile switch while the
    /// profile value is sent must not send it for the new profile; the
    /// original profile's journal keeps the clear, and replays only that.
    func testAProfileSwitchDuringAProfileWriteLeavesTheDeviceClearToItsOwnProfile() async throws {
        let suiteName = "settings-journal-clear-switch-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let firstScope = "server-a|profile-1|device"
        let scope = LockedScopeValue(firstScope)
        let journal = UserDefaultsSettingsWriteJournal(defaults: defaults, scopeProvider: { scope.value })
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30), journal: journal)
        _ = try await flusher.effectiveValues(keys: [])
        transport.onWrite = { _ in
            transport.onWrite = nil
            scope.value = "server-a|profile-2|device"
        }

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        await flusher.flushNow()
        XCTAssertTrue(transport.deletes().isEmpty, "not sent under the new profile")

        scope.value = firstScope
        flusher.restorePendingWrites()
        await flusher.flushNow()
        XCTAssertEqual(transport.writes().map(\.scope), [.profile], "the stored profile value is not sent again")
        XCTAssertEqual(transport.scopedDeletes(), [.init(key: .playbackSubtitleAppearance, scope: .profileDevice)])
        XCTAssertTrue(journal.load().isEmpty)
    }

    /// The owed profile value follows every later operation on this device's
    /// value until one is sent, and waits for the revision like a profile
    /// write of the key would.
    func testAnOwedProfileValueSurvivesLaterDeviceOperations() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))

        flusher.enqueue(.playerSubtitleSyncMs, value: .int(-300), scope: .profile, clearingDeviceValue: true)
        flusher.enqueue(.playerSubtitleSyncMs, value: .int(100))
        flusher.enqueueDelete(.playerSubtitleSyncMs)
        XCTAssertEqual(flusher.unsettledScopedValues()[.playerSubtitleSyncMs]?.scope, .profile)
        XCTAssertEqual(flusher.unsettledScopedValues()[.playerSubtitleSyncMs]?.value, .int(-300))
        XCTAssertTrue(flusher.hasRevisionGatedWrites)

        await flusher.flushNow()
        XCTAssertTrue(transport.writes().isEmpty, "must not guess the server's revision")

        _ = try await flusher.effectiveValues(keys: [])
        await flusher.flushNow()
        XCTAssertEqual(
            transport.writes(),
            [.init(key: .playerSubtitleSyncMs, value: .int(-300), profileId: nil, scope: .profile)]
        )
        XCTAssertEqual(transport.scopedDeletes(), [.init(key: .playerSubtitleSyncMs, scope: .profileDevice)])
        XCTAssertFalse(flusher.hasPendingWrites)
    }

    /// A failed clear is retried, and only the clear: the profile value it
    /// followed is stored, and sending it again could overwrite a newer one
    /// another device saved meanwhile.
    func testAFailedDeviceClearIsRetriedWithoutResendingTheProfileValue() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        transport.failNextDeletes(1, with: .transport(description: "offline"))

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        await flusher.flushNow()
        XCTAssertTrue(flusher.hasPendingWrites, "the clear is still owed")

        transport.succeedFromNowOn()
        await flusher.flushNow()
        XCTAssertFalse(flusher.hasPendingWrites)
        XCTAssertEqual(transport.writes().map(\.scope), [.profile])
        XCTAssertEqual(transport.scopedDeletes().count, 2)
    }

    /// The same for a clear that ran out of automatic retries: "Try Again"
    /// sends the clear, not the profile value again.
    func testRetryingAHeldDeviceClearDoesNotResendTheProfileValue() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(
            transport: transport,
            debounce: .seconds(30),
            retryPolicy: .init(maximumAutomaticRetries: 0, base: .seconds(60), maximum: .seconds(60))
        )
        _ = try await flusher.effectiveValues(keys: [])
        transport.failNextDeletes(1, with: .transport(description: "offline"))

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        await flusher.flushNow()
        XCTAssertEqual(flusher.heldKeys, [.playbackSubtitleAppearance])

        await flusher.retryHeldChanges()
        XCTAssertFalse(flusher.hasPendingWrites)
        XCTAssertEqual(transport.writes().map(\.scope), [.profile])
        XCTAssertEqual(transport.scopedDeletes().count, 2)
    }

    /// Turning the override on while a profile edit is being sent: once the
    /// profile value is stored, the device edit queued meanwhile does not
    /// send it again.
    func testADeviceEditQueuedWhileAProfileValueIsSentDoesNotSendItAgain() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        transport.onWrite = { [weak flusher] write in
            guard write.scope == .profile else { return }
            transport.onWrite = nil
            flusher?.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "small"])
        }

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        await flusher.flushNow()

        XCTAssertFalse(flusher.hasPendingWrites)
        XCTAssertEqual(transport.writes().map(\.scope), [.profile, .profileDevice])
        XCTAssertEqual(transport.writesByKey()[.playbackSubtitleAppearance]?.value, ["fontSize": "small"])
    }

    /// A profile edit that failed earlier in the same drain is still owed when
    /// the override is turned on before the drain retries it.
    func testAProfileEditThatFailedEarlierInTheDrainSurvivesTheOverrideTurningOn() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        transport.failNextWrites(1, with: .transport(description: "offline"))
        transport.onWrite = { [weak flusher] write in
            guard write.key == .playerHdrEnabled else { return }
            transport.onWrite = nil
            flusher?.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "small"])
        }

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        flusher.enqueue(.playerHdrEnabled, value: .bool(false))
        await flusher.flushNow()

        XCTAssertFalse(flusher.hasPendingWrites)
        let appearance = transport.writes().filter { $0.key == .playbackSubtitleAppearance }
        XCTAssertEqual(appearance.map(\.scope), [.profile, .profile, .profileDevice])
        XCTAssertEqual(appearance.map(\.value), [["fontSize": "large"], ["fontSize": "large"], ["fontSize": "small"]])
    }

    /// The server refusing the owed profile value does not take this
    /// device's own edit in the same write with it.
    func testARefusedOwedProfileValueStillSavesTheDeviceEdit() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        transport.failNextWrites(1, with: .invalidValue(message: "refused"))

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "small"])
        await flusher.flushNow()

        XCTAssertFalse(flusher.hasPendingWrites)
        XCTAssertEqual(transport.writes().map(\.scope), [.profile, .profileDevice])
        XCTAssertEqual(transport.writesByKey()[.playbackSubtitleAppearance]?.value, ["fontSize": "small"])
    }

    /// The refusal is reported even when the device edit sent with it has to
    /// be retried, and only once.
    func testARefusedOwedProfileValueIsReportedWhenTheDeviceEditIsRetried() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        let rejected = LockedKeys()
        flusher.observeRejections { rejected.append($0) }
        transport.failNextWrites(1, with: .invalidValue(message: "refused"))
        // The second attempt, this device's edit, fails transiently.
        let attempts = LockedKeys()
        transport.onAttemptStart = {
            attempts.append(.playbackSubtitleAppearance)
            guard attempts.value.count == 2 else { return }
            transport.failNextWrites(1, with: .transport(description: "offline"))
        }

        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "large"], scope: .profile, clearingDeviceValue: true)
        flusher.enqueue(.playbackSubtitleAppearance, value: ["fontSize": "small"])
        await flusher.flushNow()
        XCTAssertEqual(rejected.value, [.playbackSubtitleAppearance])
        XCTAssertTrue(flusher.hasPendingWrites, "the device edit is still owed")

        transport.succeedFromNowOn()
        await flusher.flushNow()
        XCTAssertFalse(flusher.hasPendingWrites)
        XCTAssertEqual(transport.writes().map(\.scope), [.profile, .profileDevice, .profileDevice])
        XCTAssertEqual(rejected.value, [.playbackSubtitleAppearance])
    }

    /// A clear that failed earlier in the running drain is still owed, so a
    /// refresh landing meanwhile does not read the device value it removes as
    /// this device's own.
    func testAClearThatFailedEarlierInTheDrainStillCountsAsOwed() async throws {
        let transport = FakeSettingsTransport()
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))
        _ = try await flusher.effectiveValues(keys: [])
        transport.failNextDeletes(1, with: .transport(description: "offline"))
        let clearsDuringDrain = LockedKeys()
        transport.onWrite = { [weak flusher] write in
            guard write.key == .playerHdrEnabled, let flusher else { return }
            clearsDuringDrain.set(Array(flusher.unsettledClears))
        }

        flusher.enqueueDelete(.playbackSubtitleAppearance)
        flusher.enqueue(.playerHdrEnabled, value: .bool(false))
        await flusher.flushNow()

        XCTAssertEqual(clearsDuringDrain.value, [.playbackSubtitleAppearance])
    }

    /// A pending profile offset on a server that stores offsets only per
    /// device lands on this device's row, and reads as this device's own.
    func testAPendingProfileOffsetReadsAsThisDevicesOwnOnAnOlderServer() async throws {
        let transport = FakeSettingsTransport()
        transport.revision = SettingKey.subtitleSyncProfileScopeRevision - 1
        let flusher = PlayerSettingsFlusher(transport: transport, debounce: .seconds(30))

        flusher.enqueue(.playerSubtitleSyncMs, value: .int(-300), scope: .profile, clearingDeviceValue: true)
        XCTAssertEqual(flusher.unsettledScopedValues()[.playerSubtitleSyncMs]?.scope, .profile)

        _ = try await flusher.effectiveValues(keys: [])
        XCTAssertEqual(flusher.unsettledScopedValues()[.playerSubtitleSyncMs]?.scope, .profileDevice)
    }

    func testTheJournalKeepsAWritesScopeAndReadsOlderEntriesAsDeviceWrites() throws {
        let suiteName = "settings-journal-write-scope-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let journal = UserDefaultsSettingsWriteJournal(defaults: defaults, scopeProvider: { "scope-a" })

        journal.save([
            .playerSubtitleSyncMs: PendingSettingWrite(
                operation: .set(.int(-500)),
                scope: .profile,
                clearsDeviceValue: true
            ),
        ])
        let restored = try XCTUnwrap(journal.load()[.playerSubtitleSyncMs])
        XCTAssertEqual(restored.scope, .profile)
        XCTAssertTrue(restored.clearsDeviceValue)

        // An entry written by a build that had no scope fields.
        journal.save([.playerHdrEnabled: PendingSettingWrite(operation: .set(.bool(false)))])
        let storageKey = "player.pendingDeviceSettingWrites.scope-a"
        var stored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: storageKey))) as? [String: Any]
        )
        var entry = try XCTUnwrap(stored[SettingKey.playerHdrEnabled.rawValue] as? [String: Any])
        entry.removeValue(forKey: "scope")
        entry.removeValue(forKey: "clearsDeviceValue")
        stored[SettingKey.playerHdrEnabled.rawValue] = entry
        defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: storageKey)

        let legacy = try XCTUnwrap(journal.load()[.playerHdrEnabled])
        XCTAssertEqual(legacy.scope, .profileDevice)
        XCTAssertFalse(legacy.clearsDeviceValue)
        XCTAssertEqual(legacy.operation, .set(.bool(false)))
    }
}
