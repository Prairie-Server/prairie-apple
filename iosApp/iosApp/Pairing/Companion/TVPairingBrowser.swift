#if os(iOS)
import Foundation
import Network

/// A discovered Apple TV waiting to be set up.
struct DiscoveredTV: Identifiable, Equatable {
    let id: String          // TXT `id` (stable device id), or endpoint string.
    let name: String        // TXT `name`.
    let state: PairingReceiverState
    let endpoint: NWEndpoint
    static func == (a: DiscoveredTV, b: DiscoveredTV) -> Bool { a.id == b.id }
}

/// Browses `_silopair._tcp` and publishes discovered TVs. Drives the
/// hands-off banner. Owns the Local Network permission prompt (triggered on
/// first browse).
@MainActor
@Observable
final class TVPairingBrowser {
    private(set) var found: [DiscoveredTV] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: PairingProtocol.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.found = results.compactMap(Self.makeTV) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        found = []
    }

    private static func makeTV(_ result: NWBrowser.Result) -> DiscoveredTV? {
        guard case let .bonjour(txt) = result.metadata else { return nil }
        let name = txt["name"] ?? "Apple TV"
        let id = txt["id"] ?? "\(result.endpoint)"
        let state = PairingReceiverState(rawValue: txt["st"] ?? "setup") ?? .setup
        return DiscoveredTV(id: id, name: name, state: state, endpoint: result.endpoint)
    }
}
#endif
