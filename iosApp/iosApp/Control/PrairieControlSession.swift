import Foundation
import Network

/// The PrairieControl channel is the shared framed-JSON LAN transport specialized
/// to `PrairieControlMessage`.
typealias PrairieControlSession = FramedJSONSession<PrairieControlMessage>

/// How the phone dials a TV. The DNS-SD type the TV was found under decides
/// it: a `_prairiecast._tcp` TV is always dialed over TLS, whatever its TXT
/// says, so nothing on the network can talk a phone down to plain TCP.
enum PrairieControlTransport: String, Codable, Equatable, Sendable {
    /// Apple TV and Android TV (`_prairiecast._tcp`): TLS-PSK.
    case tls
    /// Roku (`_prairiecast-roku._tcp`) at TXT `sec=plain`: TCP without TLS,
    /// which Roku sockets lack. The same exposure as the fixed public PSK.
    case plain
    /// Roku at TXT `sec=sealed`: TCP with every frame after the opening
    /// exchange sealed with the pairing key from the Roku's QR code.
    case sealed

    var isRoku: Bool { self != .tls }
}

extension FramedJSONSession where Message == PrairieControlMessage {
    /// Outbound side (iPhone remote): connect to a discovered Apple or
    /// Android TV.
    init(endpoint: NWEndpoint) {
        self.init(endpoint: endpoint, parameters: Self.tlsParameters())
    }

    /// Outbound side for a Roku: plain TCP, sealed when `sealing` is given.
    /// Never used for a `_prairiecast._tcp` TV.
    init(rokuEndpoint endpoint: NWEndpoint, sealing: PrairieControlSealedChannel?) {
        self.init(endpoint: endpoint, parameters: NWParameters(tls: nil, tcp: NWProtocolTCP.Options()), sealing: sealing)
    }

    static func tlsParameters() -> NWParameters {
        PrairieLANTLS.parameters(psk: "prairie-cast-v1", identity: "prairie-cast")
    }

    /// Send a final `.close` ahead of the FIN. The peer must read `.close`
    /// before EOF to tell a deliberate disconnect from a dropped connection —
    /// otherwise it auto-reconnects.
    func closeGracefully(reason: String? = nil) async {
        await closeGracefully(goodbye: .close(reason: reason))
    }
}
