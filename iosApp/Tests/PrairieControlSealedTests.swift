import Network
import XCTest
@testable import Prairie

/// Level `sealed` against the vectors in prairie-roku's
/// `tests/control/sealed.spec.bs`, which come from Node's crypto module, so
/// the phone, the Roku and the Node controller all build the same frames.
/// Recomputed for the `prairie-cast-sealed-1` label (upstream uses
/// `silo-cast-sealed-1`).
final class PrairieControlSealedTests: XCTestCase {
    private func hex(_ text: String) -> Data {
        var out = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            out.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private var key: Data { hex("000102030405060708090a0b0c0d0e0f") }

    private var keys: PrairieControlSealed.SessionKeys {
        PrairieControlSealed.sessionKeys(
            key: key,
            phoneNonce: hex("101112131415161718191a1b1c1d1e1f"),
            tvNonce: hex("202122232425262728292a2b2c2d2e2f")
        )
    }

    func testNamesTheKeyAndDerivesTheSessionKeys() {
        XCTAssertEqual(PrairieControlSealed.keyId(key), "be45cb26")
        XCTAssertEqual(hexString(keys.encryption), "de4408ef0430df2420f995f133eefda8")
        XCTAssertEqual(hexString(keys.authentication), "893dad33d613cc5e388b578ff53a9b8f27e9d3af04088f907b5690c5026d8e86")
        XCTAssertEqual(hexString(keys.iv), "3f808d9779b57fb50f67a59dac88e257")
    }

    func testReadsTheKeyFromThePairingLinksBase32() {
        XCTAssertEqual(PrairieControlSealed.base32Decode("AAAQEAYEAUDAOCAJBIFQYDIOB4"), key)
        XCTAssertEqual(PrairieControlSealed.base32Decode("aaaqeayeaudaocajbifqydiob4"), key)
        XCTAssertNil(PrairieControlSealed.base32Decode("AAAQ-EAYE"))
    }

    func testSealsAPhoneFrameAsTheReferenceDoes() throws {
        let body = try PrairieControlSealed.seal(
            Data(#"{"type":"pong","v":2}"#.utf8), keys: keys, direction: PrairieControlSealed.fromPhone,
            seq: 1, iv: hex("ffeeddccbbaa99887766554433221100")
        )
        XCTAssertEqual(hexString(body), "0000000000000001ffeeddccbbaa998877665544332211001e5a6529eac949e50135295d2a2db70480347b2340c8493d25ac3f86bac2b586dc5c559e11e77ec302821eb802b3273d530a9e835850c3a4d1702602e6bc20f5")
    }

    func testOpensARokuFrame() throws {
        let body = hex("0000000000000000e3c9c8e329cba6d9317f6e0442a21dd969b8d650fe4663789e80397f935b3a8497c3ce913b7b0d69f33ea9f748ca5be64600b830e4719704f026113ebd311fe164773a1d17b2ea8c66800574f614cbf0")
        let text = try PrairieControlSealed.open(body, keys: keys, direction: PrairieControlSealed.fromTV, seq: 0)
        XCTAssertEqual(String(decoding: text, as: UTF8.self), #"{"type":"ping","v":2}"#)
    }

    func testRefusesATamperedReplayedReorderedOrMisdirectedFrame() throws {
        let plaintext = Data(#"{"type":"ping","v":2}"#.utf8)
        let body = try PrairieControlSealed.seal(plaintext, keys: keys, direction: PrairieControlSealed.fromTV,
            seq: 3, iv: PrairieControlSealed.randomBytes(16))
        XCTAssertEqual(try PrairieControlSealed.open(body, keys: keys, direction: PrairieControlSealed.fromTV, seq: 3), plaintext)
        XCTAssertThrowsError(try PrairieControlSealed.open(body, keys: keys, direction: PrairieControlSealed.fromTV, seq: 4), "replayed")
        XCTAssertThrowsError(try PrairieControlSealed.open(body, keys: keys, direction: PrairieControlSealed.fromTV, seq: 2), "reordered")
        XCTAssertThrowsError(try PrairieControlSealed.open(body, keys: keys, direction: PrairieControlSealed.fromPhone, seq: 3), "the other direction")
        var tampered = body
        tampered[30] &+= 1
        XCTAssertThrowsError(try PrairieControlSealed.open(tampered, keys: keys, direction: PrairieControlSealed.fromTV, seq: 3), "tampered")
        let other = PrairieControlSealed.sessionKeys(key: hex("0f0e0d0c0b0a09080706050403020100"),
            phoneNonce: hex("101112131415161718191a1b1c1d1e1f"), tvNonce: hex("202122232425262728292a2b2c2d2e2f"))
        XCTAssertThrowsError(try PrairieControlSealed.open(body, keys: other, direction: PrairieControlSealed.fromTV, seq: 3), "another key")
        XCTAssertThrowsError(try PrairieControlSealed.open(hex("00"), keys: keys, direction: PrairieControlSealed.fromTV, seq: 3), "short")
    }

    /// The channel numbers each direction from 0 and keys only from a
    /// `sealed_hello` for its own key.
    func testChannelKeysFromTheTVsHelloAndCountsEachDirection() throws {
        var channel = PrairieControlSealedChannel(key: key, nonce: hex("101112131415161718191a1b1c1d1e1f"))
        let opening = try XCTUnwrap(JSONSerialization.jsonObject(with: channel.openingFrame) as? [String: Any])
        XCTAssertEqual(opening["type"] as? String, "sealed_hello")
        XCTAssertEqual(opening["keyId"] as? String, "be45cb26")
        XCTAssertEqual(opening["nonce"] as? String, "EBESExQVFhcYGRobHB0eHw")
        XCTAssertFalse(channel.isKeyed)

        var refused = channel
        XCTAssertThrowsError(try refused.receiveOpening(Data(#"{"type":"close","v":2,"close":{"reason":"unauthorized"}}"#.utf8))) {
            XCTAssertEqual($0 as? PrairieControlSealedError, .pairingRefused)
        }
        XCTAssertThrowsError(try refused.receiveOpening(Data(#"{"type":"sealed_hello","v":1,"keyId":"00000000","nonce":"ICEiIyQlJicoKSorLC0uLw"}"#.utf8)))

        try channel.receiveOpening(Data(#"{"type":"sealed_hello","v":1,"keyId":"BE45CB26","nonce":"ICEiIyQlJicoKSorLC0uLw"}"#.utf8))
        XCTAssertTrue(channel.isKeyed)
        for seq: UInt64 in 0...1 {
            let sealed = try channel.seal(Data("frame \(seq)".utf8))
            XCTAssertEqual(try PrairieControlSealed.open(sealed, keys: keys, direction: PrairieControlSealed.fromPhone, seq: seq),
                Data("frame \(seq)".utf8))
            let fromTV = try PrairieControlSealed.seal(Data("reply \(seq)".utf8), keys: keys,
                direction: PrairieControlSealed.fromTV, seq: seq, iv: PrairieControlSealed.randomBytes(16))
            XCTAssertEqual(try channel.open(fromTV), Data("reply \(seq)".utf8))
        }
    }

    // MARK: - Over a socket

    /// A phone session to a stand-in Roku: the opening frames cross in
    /// plain, a frame queued before keying waits for the keys, and every
    /// later frame is sealed both ways.
    func testSessionSealsFramesAfterTheOpeningExchange() async throws {
        let tv = try await LoopbackTV.start()
        defer { tv.stop() }
        let session = PrairieControlSession(rokuEndpoint: tv.endpoint, sealing: PrairieControlSealedChannel(key: key))
        let inbound = await session.open()
        session.enqueue(.ping)

        let connection = try await tv.accept()
        let hello = try JSONSerialization.jsonObject(with: try await tv.readFrame(connection)) as? [String: Any]
        XCTAssertEqual(hello?["keyId"] as? String, "be45cb26")
        let phoneNonce = try XCTUnwrap(PrairieControlSealed.fromBase64url(try XCTUnwrap(hello?["nonce"] as? String)))
        let tvNonce = PrairieControlSealed.randomBytes(16)
        try await tv.writeFrame(connection, Data(
            #"{"type":"sealed_hello","v":1,"keyId":"be45cb26","nonce":"\#(PrairieControlSealed.base64url(tvNonce))"}"#.utf8))
        let keys = PrairieControlSealed.sessionKeys(key: key, phoneNonce: phoneNonce, tvNonce: tvNonce)

        let ping = try PrairieControlSealed.open(try await tv.readFrame(connection), keys: keys,
            direction: PrairieControlSealed.fromPhone, seq: 0)
        XCTAssertEqual(try JSONDecoder().decode(PrairieControlMessage.self, from: ping), .ping)

        try await tv.writeFrame(connection, try PrairieControlSealed.seal(Data(#"{"type":"pong","v":2}"#.utf8),
            keys: keys, direction: PrairieControlSealed.fromTV, seq: 0, iv: PrairieControlSealed.randomBytes(16)))
        var iterator = inbound.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first, .pong)
        await session.close()
    }

    /// A Roku that doesn't hold the key answers with a plain close; the
    /// phone's waiting send fails with the reason, not a bare "closed".
    func testRefusedPairingFailsTheWaitingSend() async throws {
        let tv = try await LoopbackTV.start()
        defer { tv.stop() }
        let session = PrairieControlSession(rokuEndpoint: tv.endpoint, sealing: PrairieControlSealedChannel(key: key))
        // Held to the end: dropping the inbound stream closes the session.
        let inbound = await session.open()
        let send = Task { try await session.send(.ping) }

        let connection = try await tv.accept()
        _ = try await tv.readFrame(connection)
        try await tv.writeFrame(connection, Data(#"{"type":"close","v":2,"close":{"reason":"unauthorized"}}"#.utf8))

        do {
            try await send.value
            XCTFail("the send should fail")
        } catch {
            XCTAssertEqual(error as? PrairieControlSealedError, .pairingRefused)
        }
        withExtendedLifetime(inbound) {}
    }
}

/// A plain TCP listener on the loopback interface that plays a Roku's part
/// one raw frame at a time.
private final class LoopbackTV: @unchecked Sendable {
    private let listener: NWListener
    private let connections: AsyncStream<NWConnection>
    let endpoint: NWEndpoint

    private init(listener: NWListener, connections: AsyncStream<NWConnection>, port: NWEndpoint.Port) {
        self.listener = listener
        self.connections = connections
        endpoint = .hostPort(host: "127.0.0.1", port: port)
    }

    static func start() async throws -> LoopbackTV {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let (connections, sink) = AsyncStream<NWConnection>.makeStream()
        listener.newConnectionHandler = { sink.yield($0) }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
        return LoopbackTV(listener: listener, connections: connections, port: port)
    }

    func accept() async throws -> NWConnection {
        var iterator = connections.makeAsyncIterator()
        guard let connection = await iterator.next() else { throw CancellationError() }
        connection.start(queue: .main)
        return connection
    }

    func readFrame(_ connection: NWConnection) async throws -> Data {
        let head = try await receive(connection, count: 4)
        let length = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        return try await receive(connection, count: Int(length))
    }

    func writeFrame(_ connection: NWConnection, _ body: Data) async throws {
        let framed = try PrairieFrame.encode(body)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func stop() {
        listener.cancel()
    }

    private func receive(_ connection: NWConnection, count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
    }
}
