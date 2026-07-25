//
//  SharedDefaultsTests.swift
//  PrairieTests
//

import XCTest
import Foundation
@testable import Prairie

final class SharedDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var standardName: String!
    private var suite: UserDefaults!
    private var standard: UserDefaults!
    private var defaults: SharedDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SharedDefaultsTests.suite.\(UUID().uuidString)"
        standardName = "SharedDefaultsTests.standard.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        standard = UserDefaults(suiteName: standardName)!
        defaults = SharedDefaults(suite: suite, standard: standard)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        standard.removePersistentDomain(forName: standardName)
        super.tearDown()
    }

    func testStringWriteMirrorsToSuiteAndStandard() {
        defaults.set("https://ex", forKey: SharedStorage.serverUrlKey)
        XCTAssertEqual(suite.string(forKey: SharedStorage.serverUrlKey), "https://ex")
        XCTAssertEqual(standard.string(forKey: SharedStorage.serverUrlKey), "https://ex")
        XCTAssertEqual(defaults.string(forKey: SharedStorage.serverUrlKey), "https://ex")
    }

    func testReadFallsBackToStandardWhenSuiteMissing() {
        standard.set("legacy", forKey: "profileId")
        XCTAssertEqual(defaults.string(forKey: "profileId"), "legacy")
        XCTAssertTrue(defaults.containsObject(forKey: "profileId"))
    }

    func testBoolDataAndRemove() {
        defaults.set(true, forKey: "flag")
        XCTAssertTrue(defaults.bool(forKey: "flag"))
        let payload = Data("hi".utf8)
        defaults.set(payload, forKey: "blob")
        XCTAssertEqual(defaults.data(forKey: "blob"), payload)
        defaults.removeObject(forKey: "flag")
        defaults.removeObject(forKey: "blob")
        XCTAssertFalse(defaults.containsObject(forKey: "flag"))
        XCTAssertNil(defaults.data(forKey: "blob"))
    }

    func testNilStringRemovesKey() {
        defaults.set("x", forKey: "k")
        defaults.set(nil as String?, forKey: "k")
        XCTAssertNil(defaults.string(forKey: "k"))
    }
}
