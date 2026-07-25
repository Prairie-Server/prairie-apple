#if os(iOS)
import Foundation
import Network

struct PrairieControlTarget: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    let serverId: String
    let serverName: String?
    let protocolVersion: Int
    /// The TV's advertised "currently playing" flag (Bonjour TXT `playing`).
    /// False for TVs running an older build that doesn't advertise it.
    var isPlaying: Bool = false

    static func == (lhs: PrairieControlTarget, rhs: PrairieControlTarget) -> Bool {
        lhs.id == rhs.id && lhs.isPlaying == rhs.isPlaying
            && lhs.serverId == rhs.serverId && lhs.protocolVersion == rhs.protocolVersion
    }
}

@MainActor
@Observable
final class PrairieControlBrowser {
    private(set) var found: [PrairieControlTarget] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: PrairieControlProtocol.serviceType, domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.found = results
                    .compactMap { Self.makeTarget($0) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        found = []
    }

    private static func makeTarget(_ result: NWBrowser.Result) -> PrairieControlTarget? {
        guard case let .bonjour(txt) = result.metadata else { return nil }
        guard let serverId = txt["server"], !serverId.isEmpty else { return nil }
        let deviceId = txt["id"] ?? "\(result.endpoint)"
        let name = txt["name"] ?? "Prairie TV"
        return PrairieControlTarget(
            id: deviceId,
            name: name,
            endpoint: result.endpoint,
            serverId: serverId,
            serverName: txt["serverName"],
            protocolVersion: Int(txt["v"] ?? "1") ?? 1,
            isPlaying: txt["playing"] == "1"
        )
    }
}
#endif
