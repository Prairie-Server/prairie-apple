import Foundation

@main
struct DetailVersionSelectionTests {
    static func main() {
        testAutoDisplayPrefersBestVersionOverFirstReturnedVersion()
        testEditionsGroupVersionsByEditionLabel()
        testEditionForFileIdFindsOwningEdition()
        testFileVersionDecodesIntroAndCreditsMarkers()
        testAudiobookDetailAndPresentationFieldsDecode()
        testAudiobookMediaTypeNormalization()
        testLibrariesResponseDecodesBareArray()
        testAudioPlaybackTimelineMapsGlobalAndLocalTime()
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

    private static func decodedVersions(_ json: String) -> [FileVersion] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode([FileVersion].self, from: Data(json.utf8))
    }

    private static func testEditionsGroupVersionsByEditionLabel() {
        let versions = decodedVersions("""
        [
          { "file_id": 1, "edition": "Director's Cut", "resolution": "4K" },
          { "file_id": 2, "edition": "Director's Cut", "resolution": "1080p" },
          { "file_id": 3, "resolution": "1080p" }
        ]
        """)

        let editions = PlaybackEditions.editions(from: versions)

        precondition(editions.count == 2, "Expected 2 editions; got \(editions.count)")
        precondition(editions[0].label == "Director's Cut", "First edition label wrong: \(editions[0].label)")
        precondition(editions[0].versions.count == 2, "Director's Cut should hold 2 versions")
        precondition(editions[1].label == "Standard", "Untitled edition should be labeled Standard; got \(editions[1].label)")
    }

    private static func testEditionForFileIdFindsOwningEdition() {
        let versions = decodedVersions("""
        [
          { "file_id": 1, "edition": "Theatrical", "resolution": "1080p" },
          { "file_id": 2, "edition": "Extended", "resolution": "1080p" }
        ]
        """)

        let edition = PlaybackEditions.edition(forFileId: 2, in: versions)

        precondition(edition?.label == "Extended", "fileId 2 should resolve to Extended; got \(edition?.label ?? "nil")")
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

    private static func testAudiobookDetailAndPresentationFieldsDecode() {
        let json = """
        {
          "content_id": "book-1",
          "type": "audiobook",
          "title": "The Test Book",
          "user_data": {
            "played": false,
            "position_seconds": 95,
            "duration_seconds": 1800
          },
          "audiobook": {
            "authors": [{ "name": "Ada Writer" }],
            "narrators": [{ "name": "Nia Voice" }],
            "publisher": "Silo Press",
            "total_duration_seconds": 1800
          },
          "versions": [
            {
              "file_id": 7,
              "file_name": "Part 1.m4b",
              "codec_audio": "aac",
              "container": "m4b",
              "duration": 900,
              "presentation_kind": "audiobook_part",
              "presentation_group_key": "book-1",
              "presentation_part_index": 1,
              "presentation_part_total": 2
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let detail = try! decoder.decode(ItemDetail.self, from: Data(json.utf8))

        precondition(detail.type == "audiobook")
        precondition(detail.audiobook?.authors.first?.name == "Ada Writer")
        precondition(detail.audiobook?.narrators.first?.name == "Nia Voice")
        precondition(detail.audiobook?.publisher == "Silo Press")
        precondition(detail.audiobook?.totalDurationSeconds == 1800)
        precondition(detail.versions?.first?.presentationKind == "audiobook_part")
        precondition(detail.versions?.first?.presentationGroupKey == "book-1")
        precondition(detail.versions?.first?.presentationPartIndex == 1)
        precondition(detail.versions?.first?.presentationPartTotal == 2)
    }

    private static func testAudiobookMediaTypeNormalization() {
        precondition(SiloMediaType.isAudiobook("audiobook"))
        precondition(SiloMediaType.isAudiobook("audiobooks"))
        precondition(SiloMediaType.isAudiobook("book"))
        precondition(SiloMediaType.isAudiobook("books"))
        precondition(!SiloMediaType.isAudiobook("movies"))

        let library = Library(
            id: 10,
            name: "Audiobooks",
            type: "audiobooks",
            sortOrder: nil,
            posterUrl: nil
        )
        precondition(library.isAudiobookLibrary)
    }

    private static func testLibrariesResponseDecodesBareArray() {
        let json = """
        [
          { "id": 1, "name": "Movies", "type": "movies" },
          { "id": 10, "name": "Audiobooks", "type": "audiobooks" }
        ]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try! decoder.decode(LibrariesResponse.self, from: Data(json.utf8))

        precondition(response.libraries.count == 2)
        precondition(response.libraries[1].isAudiobookLibrary)
    }

    private static func testAudioPlaybackTimelineMapsGlobalAndLocalTime() {
        let tracks = [
            AudioPlaybackTrack(
                index: 0,
                fileId: 7,
                fileName: nil,
                durationSeconds: 120,
                startOffsetSeconds: 0
            ),
            AudioPlaybackTrack(
                index: 1,
                fileId: 8,
                fileName: nil,
                durationSeconds: 180,
                startOffsetSeconds: 120
            ),
        ]

        precondition(AudioPlaybackTimeline.trackIndex(at: -10, tracks: tracks) == 0)
        precondition(AudioPlaybackTimeline.trackIndex(at: 119.9, tracks: tracks) == 0)
        precondition(AudioPlaybackTimeline.trackIndex(at: 120, tracks: tracks) == 1)
        precondition(AudioPlaybackTimeline.trackIndex(at: 500, tracks: tracks) == 1)

        let second = tracks[1]
        precondition(AudioPlaybackTimeline.localTime(for: 135, in: second) == 15)
        precondition(AudioPlaybackTimeline.localTime(for: 999, in: second) == 180)
        precondition(AudioPlaybackTimeline.globalTime(for: 45, in: second) == 165)
        precondition(AudioPlaybackTimeline.globalTime(for: -1, in: second) == 120)
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
