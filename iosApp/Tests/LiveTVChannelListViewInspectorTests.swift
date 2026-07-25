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
}
