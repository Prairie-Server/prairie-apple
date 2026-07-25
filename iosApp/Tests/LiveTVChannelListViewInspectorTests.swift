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

    func testPopulatedListExposesChannelListAccessibilityId() throws {
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
        let list = try view.inspect().find(viewWithAccessibilityIdentifier: "livetv-channel-list")
        XCTAssertNotNil(list)
        let name = try view.inspect().find(text: "KXYZ-HD")
        XCTAssertEqual(try name.string(), "KXYZ-HD")
    }
}
