#if os(tvOS)
import Foundation
import Network
import OSLog

/// Advertises `_silopair._tcp` on the LAN and hands the first inbound
/// connection to a `PairingSession`. One connection at a time; later peers
/// are rejected as busy.
@MainActor
final class TVPairingAdvertiser {
    private var listener: NWListener?
    private var busy = false
    private static let logger = Logger(subsystem: "com.continuum.app", category: "pairing.advertiser")

    /// - Parameter onConnection: called on the main actor with an opened
    ///   session + its inbound stream for the coordinator to drive.
    func start(onConnection: @escaping (PairingSession, AsyncThrowingStream<PairingMessage, Error>) -> Void) {
        stop()
        let device = AppleDeviceIdentity.current
        let txt = NWTXTRecord([
            "v": String(PairingProtocol.version),
            "name": device.name,
            "id": device.id,
            "st": PairingReceiverState.setup.rawValue
        ])
        do {
            let listener = try NWListener(using: PairingSession.tlsParameters())
            listener.service = NWListener.Service(name: device.name, type: PairingProtocol.serviceType, txtRecord: txt)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { return }
                    if self.busy { connection.cancel(); return }
                    self.busy = true
                    let session = PairingSession(connection: connection)
                    let stream = await session.open()
                    onConnection(session, stream)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Self.logger.error("listener failed: \(String(describing: error), privacy: .public)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            Self.logger.error("failed to start listener: \(String(describing: error), privacy: .public)")
        }
    }

    /// Allow a new connection after the previous session ended.
    func release() { busy = false }

    func stop() {
        listener?.cancel()
        listener = nil
        busy = false
    }
}
#endif
