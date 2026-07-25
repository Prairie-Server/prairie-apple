import Foundation
import Network

/// The PrairieControl channel is the shared framed-JSON LAN transport specialized
/// to `PrairieControlMessage`.
typealias PrairieControlSession = FramedJSONSession<PrairieControlMessage>

extension FramedJSONSession where Message == PrairieControlMessage {
    /// Outbound side (iPhone remote): connect to a discovered receiver.
    init(endpoint: NWEndpoint) {
        self.init(endpoint: endpoint, parameters: Self.tlsParameters())
    }

    static func tlsParameters() -> NWParameters {
        PrairieLANTLS.parameters(psk: "prairie-cast-v1", identity: "prairie-cast")
    }

    /// Send a final `.close` ahead of the FIN. The peer must read `.close`
    /// before EOF to tell a deliberate disconnect from a dropped connection —
    /// otherwise it auto-reconnects.
    func closeGracefully() async {
        await closeGracefully(goodbye: .close)
    }
}
