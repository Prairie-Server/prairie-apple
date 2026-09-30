import Foundation
import XCTest
@testable import Prairie

/// Stats-for-nerds detail Prairie adds on top of Aether's telemetry: the
/// event ring buffer, the plan summary, and the redacted stream path.
final class PlaybackDiagnosticsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Event ring buffer

    func testEventLogKeepsOnlyTheNewestEntriesInOrder() {
        var log = PlaybackEventLog(capacity: 8)
        for index in 0..<11 {
            log.record("event \(index)", at: t0.addingTimeInterval(Double(index)))
        }

        XCTAssertEqual(log.entries.count, 8)
        XCTAssertEqual(log.entries.first?.message, "event 3")
        XCTAssertEqual(log.entries.last?.message, "event 10")
        XCTAssertEqual(log.newestFirst.map(\.message).prefix(2), ["event 10", "event 9"])
    }

    func testEventLogCollapsesConsecutiveDuplicatesSoAnErrorIsNotFlushed() {
        var log = PlaybackEventLog(capacity: 3)
        log.record("sourceRefused: 403", kind: .error, at: t0)
        for offset in 1...10 {
            log.record("Rebuffering", kind: .warning, at: t0.addingTimeInterval(Double(offset)))
        }

        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries[0].kind, .error)
        XCTAssertEqual(log.entries[1].repeatCount, 10)
        XCTAssertEqual(log.entries[1].at, t0.addingTimeInterval(10))
        XCTAssertEqual(log.entries[1].displayMessage, "Warning: Rebuffering ×10")
    }

    func testEventLogDoesNotCollapseTheSameMessageAtADifferentSeverity() {
        var log = PlaybackEventLog()
        log.record("Stalled", kind: .warning, at: t0)
        log.record("Stalled", kind: .error, at: t0)

        XCTAssertEqual(log.entries.map(\.kind), [.warning, .error])
    }

    func testEventLogIgnoresBlankMessagesAndClampsCapacity() {
        var log = PlaybackEventLog(capacity: 0)
        log.record("   \n", at: t0)
        XCTAssertTrue(log.entries.isEmpty)

        log.record("a", at: t0)
        log.record("b", at: t0)
        XCTAssertEqual(log.capacity, 1)
        XCTAssertEqual(log.entries.map(\.message), ["b"])

        log.removeAll()
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testEventLogRedactsCredentialsAndBoundsLength() {
        var log = PlaybackEventLog()
        log.record(
            "Load failed for https://media.example.test/api/v2/stream/42?st=supersecret-token&x=1",
            kind: .error,
            at: t0
        )
        log.record(String(repeating: "x", count: 500), at: t0)

        let message = log.entries[0].message
        XCTAssertFalse(message.contains("supersecret-token"), message)
        XCTAssertLessThanOrEqual(log.entries[1].message.count, PlaybackEventLog.maxMessageLength)
    }

    func testEntryFormatsTimeAndSeverity() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let entry = PlaybackEventLog.Entry(
            at: Date(timeIntervalSince1970: 3_600 * 13 + 60 * 4 + 31),
            kind: .error,
            message: "sourceRefused: 403"
        )

        XCTAssertEqual(entry.timeLabel(timeZone: utc), "13:04:31")
        XCTAssertEqual(entry.displayMessage, "Error: sourceRefused: 403")
    }

    func testStatsEventRowsAreNewestFirstWithStableIdentity() {
        var log = PlaybackEventLog()
        log.record("First frame", at: t0)
        log.record("Rebuffering", kind: .warning, at: t0)
        log.record("Quality: 1080p", at: t0)
        var stats = PlaybackStats.empty
        stats.recentEvents = log.entries

        let rows = stats.eventRows(limit: 2)
        XCTAssertEqual(rows.map(\.message), ["Quality: 1080p", "Warning: Rebuffering"])
        XCTAssertEqual(rows.map(\.id), [0, 1])
        XCTAssertEqual(rows[1].kind, .warning)
        XCTAssertFalse(stats.hasRows, "Events alone must not count as projected stats rows")
    }

    // MARK: - Plan summary

    func testPlanSummaryDescribesMethodRecipeAndReason() {
        let summary = PlaybackPlanSummary(
            delivery: "server_remux_progressive",
            container: "mp4",
            videoCodec: "hevc",
            width: 3840,
            height: 1600,
            dynamicRange: "hdr10",
            audioCodec: "aac",
            audioChannels: 2,
            bitrateKbps: 18_000,
            reason: "audio_adaptation"
        )

        XCTAssertEqual(summary.method, "Remux (progressive)")
        XCTAssertEqual(summary.detailLine, "MP4 · HEVC 3840×1600 HDR10 · AAC 2ch · 18.0 Mbps")
        XCTAssertEqual(summary.reasonLabel, "audio adaptation")
    }

    func testPlanSummaryMethodCoversEveryDelivery() {
        XCTAssertEqual(PlaybackPlanSummary.method(forDelivery: "original_http"), "Direct play")
        XCTAssertEqual(PlaybackPlanSummary.method(forDelivery: "server_remux_hls"), "Remux (HLS)")
        XCTAssertEqual(PlaybackPlanSummary.method(forDelivery: "server_transcode_hls"), "Transcode (HLS)")
        XCTAssertEqual(PlaybackPlanSummary.method(forDelivery: "future_route"), "future route")
        XCTAssertEqual(PlaybackPlanSummary.method(forDelivery: ""), "Unknown")
    }

    func testPlanSummaryOmitsSDRAndEmptyFields() {
        let summary = PlaybackPlanSummary(delivery: "original_http", videoCodec: "h264", dynamicRange: "sdr")
        XCTAssertEqual(summary.detailLine, "H.264")
        XCTAssertNil(PlaybackPlanSummary(delivery: "original_http", container: " ").detailLine)
        XCTAssertNil(PlaybackPlanSummary(delivery: "original_http", reason: "").reasonLabel)
    }

    func testPlanSummaryReadsTheServerPlanFixture() throws {
        let plan = try XCTUnwrap(
            PlaybackV3FixtureTestSupport.v2Decision(bundleClass: Self.self).playbackPlan
        )
        let summary = PlaybackPlanSummary(plan: plan)

        XCTAssertEqual(summary.method, "Direct play")
        XCTAssertEqual(summary.detailLine, "MP4 · H.264 1920×1080 · AAC 2ch · 8.0 Mbps")
        XCTAssertEqual(summary.reasonLabel, "validated original playback")
    }

    // MARK: - Stream path

    func testStreamPathStripsQueryIdsAndUserInfo() throws {
        let url = try XCTUnwrap(URL(
            string: "https://user:pass@media.example.test/api/v2/stream/11111111-1111-4111-8111-111111111111?st=secret#frag"
        ))
        let described = try XCTUnwrap(PlaybackStreamPath.describe(url))

        XCTAssertEqual(described, "Remote · /api/v2/stream/:id")
        XCTAssertFalse(described.contains("secret"))
        XCTAssertFalse(described.contains("pass"))
    }

    func testStreamPathNamesLoopbackAndKeepsManifestNames() throws {
        let url = try XCTUnwrap(URL(
            string: "http://127.0.0.1:52011/live-hls/aB3dE5fG7hJ9kL1m/master.m3u8?token=abc"
        ))
        XCTAssertEqual(
            PlaybackStreamPath.describe(url),
            "Loopback proxy · /live-hls/:id/master.m3u8"
        )
        XCTAssertEqual(
            PlaybackStreamPath.describe(URL(string: "http://localhost:8080/")),
            "Loopback proxy"
        )
    }

    func testStreamPathHidesMediaFilenamesAndOfflineFiles() throws {
        let remote = try XCTUnwrap(URL(string: "https://cdn.example.test/items/Secret.Title.2024.mkv"))
        XCTAssertEqual(PlaybackStreamPath.describe(remote), "Remote · /items/[media]")

        let offline = URL(fileURLWithPath: "/var/mobile/Downloads/Secret Title.mp4")
        XCTAssertEqual(PlaybackStreamPath.describe(offline), "Offline file")
        XCTAssertNil(PlaybackStreamPath.describe(nil))
    }

    // MARK: - Stats rows

    func testPlanRowsLeadTheCompactOverlay() {
        var stats = PlaybackStats.empty
        stats.route = "Aether remote HLS"
        stats.playbackMethod = "Transcode (HLS)"
        stats.plan = "TS · H.264 1920×1080 · AAC 2ch"
        stats.plannerReason = "video codec unsupported"
        stats.quality = "Auto"
        stats.audioTrack = "English · 5.1 · EAC3 (track 2)"
        stats.streamPath = "Remote · /api/v2/stream/:id"

        let compactLabels = stats.compactRows.map(\.0)
        XCTAssertEqual(
            compactLabels,
            ["Route", "Method", "Plan", "Planner reason", "Quality", "Audio track", "Stream path"]
        )
        XCTAssertEqual(stats.planRows.count, 6)
        XCTAssertTrue(stats.hasRows)
    }
}
