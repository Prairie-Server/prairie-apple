import Foundation

@main
struct DetailVersionSelectionTests {
    static func main() {
        testAutoDisplayPrefersBestVersionOverFirstReturnedVersion()
        testFileVersionDecodesIntroAndCreditsMarkers()
        testRealtimeMarkersUpdatedEventDecodesPayload()
    }

    private static func testAutoDisplayPrefersBestVersionOverFirstReturnedVersion() {
        let versions = [
            version(fileId: 10, resolution: "1080p"),
            version(fileId: 20, resolution: "4K")
        ]

        let selected = DetailVersionSelection.displayVersion(
            versions: versions,
            selectedFileId: nil,
            lastFileId: nil
        )

        precondition(
            selected?.fileId == 20,
            "Auto should display the best version playback will choose; got \(selected?.fileId.description ?? "nil")"
        )
    }

    private static func version(fileId: Int, resolution: String?) -> FileVersion {
        FileVersion(
            fileId: fileId,
            fileName: nil,
            resolution: resolution,
            codecVideo: "hevc",
            codecAudio: nil,
            hdr: nil,
            container: nil,
            fileSize: nil,
            duration: nil,
            bitrate: nil,
            videoTracks: nil,
            audioTracks: nil,
            subtitleTracks: nil,
            chapters: nil,
            intro: nil,
            credits: nil
        )
    }

    private static func testFileVersionDecodesIntroAndCreditsMarkers() {
        let json = """
        {
          "file_id": 42,
          "file_name": "Episode.mkv",
          "intro": { "start": 12.5, "end": 74.25 },
          "credits": { "start": 1440.0, "end": 1500.0 }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let version = try! decoder.decode(FileVersion.self, from: Data(json.utf8))

        precondition(version.fileId == 42)
        precondition(version.intro?.start == 12.5)
        precondition(version.intro?.end == 74.25)
        precondition(version.credits?.start == 1440.0)
        precondition(version.credits?.end == 1500.0)
    }

    private static func testRealtimeMarkersUpdatedEventDecodesPayload() {
        let json = """
        {
          "type": "event",
          "session_id": "session-1",
          "name": "markers_updated",
          "payload": {
            "session_id": "session-1",
            "file_id": 42,
            "intro": { "start": 12.0, "end": 75.0 },
            "credits": null
          }
        }
        """

        guard case .event(let event)? = parsePlaybackRealtimeInboundMessage(Data(json.utf8)) else {
            preconditionFailure("Expected markers_updated event")
        }

        precondition(event.sessionId == "session-1")
        precondition(event.name == .markersUpdated)

        guard let payload = PlaybackRealtimeMarkersUpdatedPayload(payload: event.payload) else {
            preconditionFailure("Expected markers_updated payload")
        }
        precondition(payload.sessionId == "session-1")
        precondition(payload.fileId == 42)
        precondition(payload.intro?.start == 12.0)
        precondition(payload.intro?.end == 75.0)
        precondition(payload.credits == nil)
        precondition(payload.introUpdate == .set(TimeRange(start: 12.0, end: 75.0)))
        precondition(payload.creditsUpdate == .clear)

        let missingMarkersPayload = PlaybackRealtimeMarkersUpdatedPayload(
            payload: ["file_id": .number(42)]
        )
        precondition(missingMarkersPayload?.introUpdate == .unchanged)
        precondition(missingMarkersPayload?.creditsUpdate == .unchanged)
    }
}
