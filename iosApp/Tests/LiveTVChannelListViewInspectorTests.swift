//
//  LiveTVChannelListViewInspectorTests.swift
//  PrairieTests
//
//  ViewInspector smoke coverage for Live TV channel-list empty/loading states.
//

import XCTest
import SwiftUI
import ViewInspector
@testable import Prairie

@MainActor
final class LiveTVChannelListViewInspectorTests: XCTestCase {

    private func host(_ view: LiveTVChannelListView) -> some View {
        view.environment(AppRouter())
    }

    func testLoadingStateExposesLoadingAccessibilityId() throws {
        let view = host(LiveTVChannelListView(
            viewModel: .preview(state: .loading)
        ))
        let loading = try view.inspect().find(viewWithAccessibilityIdentifier: "livetv-loading")
        XCTAssertNotNil(loading)
    }

    func testEmptyStateExposesEmptyAccessibilityId() throws {
        let view = host(LiveTVChannelListView(
            viewModel: .preview(state: .loaded, channels: [])
        ))
        let empty = try view.inspect().find(viewWithAccessibilityIdentifier: "livetv-empty")
        XCTAssertNotNil(empty)
        let title = try view.inspect().find(text: "No channels yet")
        XCTAssertEqual(try title.string(), "No channels yet")
    }

    func testErrorStateExposesErrorAccessibilityId() throws {
        let view = host(LiveTVChannelListView(
            viewModel: .preview(
                state: .failed(ErrorState(statusCode: nil, message: "Tuner offline"))
            )
        ))
        let error = try view.inspect().find(viewWithAccessibilityIdentifier: "livetv-error")
        XCTAssertNotNil(error)
        let message = try view.inspect().find(text: "Tuner offline")
        XCTAssertEqual(try message.string(), "Tuner offline")
    }

    func testPopulatedListOpensOnTheGuideWithEveryTab() throws {
        let channel = LiveTVChannel(
            id: "ch-1",
            tunerId: "tuner-a",
            number: "4.1",
            numberOverride: nil,
            callsign: "KXYZ-HD",
            name: "KXYZ Digital",
            logoUrl: "",
            hd: true,
            enabled: true,
            streamUrl: "",
            guideStationId: ""
        )
        let view = host(LiveTVChannelListView(
            viewModel: .preview(state: .loaded, channels: [channel])
        ))
        // ViewInspector inspects a fresh copy of the view, so a tapped tab's
        // @State does not carry into the next inspection. Check the tab bar
        // and the Guide tab the list opens on instead.
        for tab in ["guide", "channels", "recordings"] {
            XCTAssertNoThrow(try view.inspect().find(viewWithAccessibilityIdentifier: "livetv-tab-\(tab)"), tab)
        }
        let guide = try view.inspect().find(viewWithAccessibilityIdentifier: "livetv-guide")
        XCTAssertNotNil(guide)
        let noGuide = try view.inspect().find(text: "No guide data")
        XCTAssertEqual(try noGuide.string(), "No guide data")
    }
}
