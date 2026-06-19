#if os(iOS)
import Foundation
import Network

struct SiloCastTarget: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    let serverId: String
    let serverName: String?

    static func == (lhs: SiloCastTarget, rhs: SiloCastTarget) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@Observable
final class SiloCastBrowser {
    private(set) var found: [SiloCastTarget] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: SiloCastProtocol.serviceType, domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                let activeServerId = ServerRegistry.shared.activeServerId
                self.found = results
                    .compactMap { Self.makeTarget($0) }
                    .filter { target in
                        guard let activeServerId else { return false }
                        return target.serverId == activeServerId
                    }
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

    private static func makeTarget(_ result: NWBrowser.Result) -> SiloCastTarget? {
        guard case let .bonjour(txt) = result.metadata else { return nil }
        guard let serverId = txt["server"], !serverId.isEmpty else { return nil }
        let deviceId = txt["id"] ?? "\(result.endpoint)"
        let name = txt["name"] ?? "Silo TV"
        return SiloCastTarget(
            id: deviceId,
            name: name,
            endpoint: result.endpoint,
            serverId: serverId,
            serverName: txt["serverName"]
        )
    }
}
#endif
