import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Native Prairie liveness + identity (not Jellyfin `/System/Info/Public`).
enum LanDiscovery {
    static let healthPath = "/api/v1/health"

    /// Prairie default listen is `:8080`. Extra ports cover reverse-proxy / TLS setups.
    static let defaultPorts: [Int] = [8080, 8443, 443, 80]

    /// Deep LAN sweeps use a single port so a /24 finishes in reasonable time.
    static let deepScanPorts: [Int] = [8080]

    /// Same fallback prefixes Litefin uses when the NIC /24 is unknown or empty.
    static let commonCidrs: [String] = [
        "192.168.0.0/24",
        "192.168.1.0/24",
        "10.0.0.0/24",
    ]

    static let priorityLastOctets: [Int] = [1, 2, 10, 20, 50, 100, 150, 200, 254]

    struct HealthIdentity: Equatable, Sendable {
        var serverName: String
        var serverId: String
    }

    struct DiscoveryHit: Equatable, Identifiable, Sendable {
        var url: String
        var serverName: String
        var serverId: String

        var id: String { url }

        var displayName: String {
            let trimmed = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? url : trimmed
        }
    }

    struct BuildCandidatesOptions: Sendable {
        var extraCidrs: [String] = []
        var deepScan: Bool = false
        var maxHostsPerCidr: Int = 254
        /// Device IPv4s when the platform can expose them.
        var localIps: [String] = []
    }

    // MARK: - Health parsing

    /// Accepts `status` of ok / healthy / up (case-insensitive).
    static func parseHealth(_ data: Any?) -> HealthIdentity? {
        guard let record = data as? [String: Any] else { return nil }
        let status = (record["status"] as? String)?.lowercased() ?? ""
        guard status == "ok" || status == "healthy" || status == "up" else { return nil }
        return HealthIdentity(
            serverName: record["server_name"] as? String ?? "",
            serverId: record["server_id"] as? String ?? ""
        )
    }

    /// Convenience for raw JSON bytes from a health probe.
    static func parseHealthJSON(_ data: Data) -> HealthIdentity? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parseHealth(object)
    }

    // MARK: - IPv4 / CIDR helpers

    static func ipv4Parts(_ ip: String) -> [Int]? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var nums: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber),
                  let value = Int(part), (0...255).contains(value) else {
                return nil
            }
            nums.append(value)
        }
        return nums
    }

    static func formatIpv4(_ parts: [Int]) -> String {
        "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
    }

    static func parseCidr(_ cidr: String) -> (network: [Int], prefix: Int)? {
        let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slash = trimmed.firstIndex(of: "/") else { return nil }
        let ip = String(trimmed[..<slash])
        let prefixString = String(trimmed[trimmed.index(after: slash)...])
        guard let prefix = Int(prefixString), (24...32).contains(prefix),
              let parts = ipv4Parts(ip) else {
            return nil
        }
        return (parts, prefix)
    }

    static func subnetCidrForIp(_ ip: String) -> String {
        guard let parts = ipv4Parts(ip) else { return "" }
        return "\(parts[0]).\(parts[1]).\(parts[2]).0/24"
    }

    static func priorityHostsForSubnet(_ base: [Int]) -> [String] {
        guard base.count == 4 else { return [] }
        return priorityLastOctets.map { last in
            formatIpv4([base[0], base[1], base[2], last])
        }
    }

    static func allHostsForCidr(network: [Int], prefix: Int, maxHosts: Int = 254) -> [String] {
        guard network.count == 4 else { return [] }
        let bits = 32 - prefix
        if bits == 0 {
            return [formatIpv4(network)]
        }
        let count = 1 << bits
        var startOffset = 1
        var endOffset = count - 2
        if endOffset < startOffset {
            startOffset = 0
            endOffset = count - 1
        }
        var hosts: [String] = []
        var added = 0
        for offset in startOffset...endOffset {
            if added >= maxHosts { break }
            if prefix < 24 { break }
            let last = network[3] + offset
            if last > 255 { break }
            hosts.append(formatIpv4([network[0], network[1], network[2], last]))
            added += 1
        }
        return hosts
    }

    static func collectScanCidrs(extraCidrs: [String] = [], localIps: [String] = []) -> [String] {
        var cidrs: [String] = []
        var seen = Set<String>()
        for ip in localIps {
            let cidr = subnetCidrForIp(ip)
            if !cidr.isEmpty { pushUnique(&cidrs, seen: &seen, value: cidr) }
        }
        for cidr in commonCidrs {
            pushUnique(&cidrs, seen: &seen, value: cidr)
        }
        for cidr in extraCidrs {
            let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pushUnique(&cidrs, seen: &seen, value: trimmed) }
        }
        return cidrs
    }

    // MARK: - Candidate URLs

    /**
     Build probe URLs (Litefin-shaped, Prairie-native):
       1) prairie.local / prairie
       2) local NIC /24 + common 192.168.0/1 + 10.0.0 (+ optional extras)
       3) deepScan=false → priority hosts on defaultPorts
          deepScan=true  → full /24 on deepScanPorts (:8080)
     */
    static func buildCandidates(_ options: BuildCandidatesOptions = BuildCandidatesOptions()) -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        for host in ["prairie.local", "prairie"] {
            urlsForHost(host, ports: defaultPorts, seen: &seen, out: &out)
        }
        for ip in options.localIps {
            if ipv4Parts(ip) != nil {
                urlsForHost(ip, ports: defaultPorts, seen: &seen, out: &out)
            }
        }

        let cidrs = collectScanCidrs(extraCidrs: options.extraCidrs, localIps: options.localIps)
        let hostPorts = options.deepScan ? deepScanPorts : defaultPorts

        for cidr in cidrs {
            guard let parsed = parseCidr(cidr) else { continue }
            let hosts = options.deepScan
                ? allHostsForCidr(
                    network: parsed.network,
                    prefix: parsed.prefix,
                    maxHosts: options.maxHostsPerCidr
                )
                : priorityHostsForSubnet(parsed.network)
            for host in hosts {
                urlsForHost(host, ports: hostPorts, seen: &seen, out: &out)
            }
        }

        return out
    }

    static func urlsForHost(
        _ host: String,
        ports: [Int],
        seen: inout Set<String>,
        out: inout [String]
    ) {
        for port in ports {
            if port == 443 {
                pushUnique(&out, seen: &seen, value: "https://\(host)")
            } else if port == 80 {
                pushUnique(&out, seen: &seen, value: "http://\(host)")
            } else {
                pushUnique(&out, seen: &seen, value: "http://\(host):\(port)")
                if port == 8443 {
                    pushUnique(&out, seen: &seen, value: "https://\(host):\(port)")
                }
            }
        }
    }

    static func mergeHits(
        _ hits: inout [DiscoveryHit],
        url: String,
        health: HealthIdentity
    ) {
        let normalized = ServerRegistry.normalize(url: url)
        if let index = hits.firstIndex(where: { $0.url == normalized }) {
            if !health.serverName.isEmpty { hits[index].serverName = health.serverName }
            if !health.serverId.isEmpty { hits[index].serverId = health.serverId }
            return
        }
        hits.append(DiscoveryHit(
            url: normalized,
            serverName: health.serverName,
            serverId: health.serverId
        ))
    }

    /// Best-effort local IPv4 discovery via `getifaddrs`. Falls back to an
    /// empty list (callers then use `commonCidrs` only).
    static func localIpv4Addresses() -> [String] {
        #if canImport(Darwin)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ips: [String] = []
        var seen = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(MemoryLayout<sockaddr_in>.size),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            guard ipv4Parts(ip) != nil, !ip.hasPrefix("127.") else { continue }
            if seen.insert(ip).inserted {
                ips.append(ip)
            }
        }
        return ips
        #else
        return []
        #endif
    }

    private static func pushUnique(_ list: inout [String], seen: inout Set<String>, value: String) {
        let key = value.lowercased()
        guard !seen.contains(key) else { return }
        seen.insert(key)
        list.append(value)
    }
}

// MARK: - Scanner

/// Concurrent LAN health probes against Prairie `/api/v1/health`.
actor LanDiscoveryScanner {
    struct ScanOptions: Sendable {
        var extraCidrs: [String] = []
        var deepScan: Bool = false
        var maxHostsPerCidr: Int = 254
        var concurrency: Int = 24
        var timeoutMs: Int = 400
        var localIps: [String]? = nil
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 0.4
            config.timeoutIntervalForResource = 0.5
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// Probe Prairie health across LAN candidates. Prefer a priority pass
    /// first, then an optional deep pass from the UI.
    func run(
        options: ScanOptions = ScanOptions(),
        onHit: (@Sendable ([LanDiscovery.DiscoveryHit]) -> Void)? = nil,
        onProgress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil
    ) async -> [LanDiscovery.DiscoveryHit] {
        let localIps = options.localIps ?? LanDiscovery.localIpv4Addresses()
        let candidates = LanDiscovery.buildCandidates(
            LanDiscovery.BuildCandidatesOptions(
                extraCidrs: options.extraCidrs,
                deepScan: options.deepScan,
                maxHostsPerCidr: options.maxHostsPerCidr,
                localIps: localIps
            )
        )

        guard !candidates.isEmpty else { return [] }

        let timeout = TimeInterval(options.timeoutMs) / 1000.0
        let workerCount = min(options.concurrency, candidates.count)
        let state = ScanState(candidates: candidates)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask {
                    while let url = await state.nextCandidate() {
                        if Task.isCancelled { return }
                        let hit = await self.probeHealth(baseURL: url, timeout: timeout)
                        let progress = await state.markDone()
                        onProgress?(progress.done, progress.total)
                        if let hit {
                            let snapshot = await state.merge(hit)
                            onHit?(snapshot)
                        }
                    }
                }
            }
        }

        return await state.hitsSnapshot()
    }

    private func probeHealth(baseURL: String, timeout: TimeInterval) async -> LanDiscovery.DiscoveryHit? {
        let serverURL = ServerRegistry.normalize(url: baseURL)
        guard let healthURL = URL(string: serverURL + LanDiscovery.healthPath) else { return nil }

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let device = AppleDeviceIdentity.current
        request.setValue(device.id, forHTTPHeaderField: "X-Prairie-Device-Id")
        request.setValue(device.name, forHTTPHeaderField: "X-Prairie-Device-Name")
        request.setValue(device.platform, forHTTPHeaderField: "X-Prairie-Device-Platform")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let health = LanDiscovery.parseHealthJSON(data) else { return nil }
            return LanDiscovery.DiscoveryHit(
                url: serverURL,
                serverName: health.serverName,
                serverId: health.serverId
            )
        } catch {
            return nil
        }
    }
}

/// Shared mutable scan cursor + hit list for concurrent workers.
private actor ScanState {
    private let candidates: [String]
    private var nextIndex = 0
    private var done = 0
    private var hits: [LanDiscovery.DiscoveryHit] = []

    init(candidates: [String]) {
        self.candidates = candidates
    }

    func nextCandidate() -> String? {
        guard nextIndex < candidates.count else { return nil }
        let value = candidates[nextIndex]
        nextIndex += 1
        return value
    }

    func markDone() -> (done: Int, total: Int) {
        done += 1
        return (done, candidates.count)
    }

    func merge(_ hit: LanDiscovery.DiscoveryHit) -> [LanDiscovery.DiscoveryHit] {
        LanDiscovery.mergeHits(
            &hits,
            url: hit.url,
            health: LanDiscovery.HealthIdentity(
                serverName: hit.serverName,
                serverId: hit.serverId
            )
        )
        return hits
    }

    func hitsSnapshot() -> [LanDiscovery.DiscoveryHit] {
        hits
    }
}
