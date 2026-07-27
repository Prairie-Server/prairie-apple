//
//  LanDiscoveryTests.swift
//  PrairieTests
//

import XCTest
@testable import Prairie

final class LanDiscoveryTests: XCTestCase {

    func testParseHealthAcceptsOkHealthyUp() {
        let ok = LanDiscovery.parseHealth([
            "status": "ok",
            "server_name": "Prairie Home",
            "server_id": "abc",
        ])
        XCTAssertEqual(ok?.serverName, "Prairie Home")
        XCTAssertEqual(ok?.serverId, "abc")

        let healthy = LanDiscovery.parseHealth(["status": "healthy"])
        XCTAssertEqual(healthy?.serverName, "")
        XCTAssertEqual(healthy?.serverId, "")

        let up = LanDiscovery.parseHealth(["status": "UP", "server_name": "X"])
        XCTAssertEqual(up?.serverName, "X")

        XCTAssertNil(LanDiscovery.parseHealth(["status": "down"]))
        XCTAssertNil(LanDiscovery.parseHealth(nil))
        XCTAssertEqual(LanDiscovery.healthPath, "/api/v1/health")
        XCTAssertEqual(LanDiscovery.deepScanPorts.first, 8080)
    }

    func testParseHealthJSON() {
        let data = Data(#"{"status":"ok","server_name":"Lan","server_id":"1"}"#.utf8)
        let health = LanDiscovery.parseHealthJSON(data)
        XCTAssertEqual(health?.serverName, "Lan")
        XCTAssertEqual(health?.serverId, "1")

        XCTAssertNil(LanDiscovery.parseHealthJSON(Data("not-json".utf8)))
    }

    func testCidrAndPriorityHosts() {
        XCTAssertEqual(LanDiscovery.parseCidr("192.168.1.0/24")?.prefix, 24)
        XCTAssertNil(LanDiscovery.parseCidr("10.0.0.0/16"))
        XCTAssertEqual(LanDiscovery.subnetCidrForIp("192.168.1.50"), "192.168.1.0/24")

        let hosts = LanDiscovery.priorityHostsForSubnet([192, 168, 1, 0])
        XCTAssertEqual(hosts.first, "192.168.1.1")
        XCTAssertEqual(LanDiscovery.commonCidrs.first, "192.168.0.0/24")
    }

    func testBuildCandidatesIncludesCommonCidrsAndPrairieHosts() {
        let candidates = LanDiscovery.buildCandidates(
            LanDiscovery.BuildCandidatesOptions(
                extraCidrs: ["192.168.2.0/24"],
                deepScan: false,
                maxHostsPerCidr: 16
            )
        )
        let joined = candidates.joined(separator: ",")
        XCTAssertTrue(joined.contains("prairie.local"))
        XCTAssertTrue(joined.contains("192.168.2.1"))
        XCTAssertTrue(joined.contains("192.168.0.1"))
        XCTAssertTrue(joined.contains("192.168.1.1"))
        XCTAssertTrue(joined.contains("10.0.0.1"))
        XCTAssertTrue(joined.contains(":8080"))
        XCTAssertFalse(joined.contains("/System/Info"))
    }

    func testBuildCandidatesIncludesConfiguredBaseHosts() {
        let candidates = LanDiscovery.buildCandidates(
            LanDiscovery.BuildCandidatesOptions(
                extraCidrs: [],
                deepScan: false,
                maxHostsPerCidr: 16,
                baseHosts: ["prairie.lan"]
            )
        )
        let joined = candidates.joined(separator: ",")
        XCTAssertTrue(joined.contains("prairie.lan"))
    }

    func testDeepScanExpandsSlash24OnListenPortOnly() {
        let deep = LanDiscovery.buildCandidates(
            LanDiscovery.BuildCandidatesOptions(
                extraCidrs: ["192.168.9.0/24"],
                deepScan: true,
                maxHostsPerCidr: 12
            )
        )
        let joined = deep.joined(separator: ",")
        XCTAssertTrue(joined.contains("192.168.9.1:8080"))
        XCTAssertTrue(joined.contains("192.168.9.12:8080"))
        XCTAssertFalse(joined.contains("https://192.168.9.1:8080"))
        XCTAssertEqual(
            LanDiscovery.allHostsForCidr(network: [192, 168, 9, 0], prefix: 24, maxHosts: 3).count,
            3
        )
    }

    func testMergeHitsDedupesByNormalizedURL() {
        var hits: [LanDiscovery.DiscoveryHit] = []
        LanDiscovery.mergeHits(
            &hits,
            url: "https://prairie.example.com/",
            health: LanDiscovery.HealthIdentity(serverName: "One", serverId: "1")
        )
        LanDiscovery.mergeHits(
            &hits,
            url: "https://prairie.example.com",
            health: LanDiscovery.HealthIdentity(serverName: "Two", serverId: "1")
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].serverName, "Two")
        XCTAssertEqual(hits[0].url, "https://prairie.example.com")
    }

    func testBuildCandidatesProbesLocalDeviceIP() {
        let candidates = LanDiscovery.buildCandidates(
            LanDiscovery.BuildCandidatesOptions(
                deepScan: false,
                maxHostsPerCidr: 4,
                localIps: ["10.0.0.42"]
            )
        )
        XCTAssertTrue(candidates.contains(where: { $0.contains("10.0.0.42") }))
    }

    func testUrlsForHostPortRules() {
        var out: [String] = []
        var seen = Set<String>()
        LanDiscovery.urlsForHost("example.local", ports: [8080, 8443, 443, 80], seen: &seen, out: &out)
        XCTAssertTrue(out.contains("http://example.local:8080"))
        XCTAssertTrue(out.contains("http://example.local:8443"))
        XCTAssertTrue(out.contains("https://example.local:8443"))
        XCTAssertTrue(out.contains("https://example.local"))
        XCTAssertTrue(out.contains("http://example.local"))
    }
}
