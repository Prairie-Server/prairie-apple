import Foundation
import XCTest
@testable import Prairie

/// The unauthenticated identity, branding and connections reads a server is
/// matched and named with, through `HTTPClient` over the shared stub, plus
/// the endpoint model those reads produce.
final class ServerIdentityProbeTests: XCTestCase {
    private let serverURL = "https://identity.example"
    private var stub = APIv2TestStub()

    override func setUp() {
        super.setUp()
        stub = APIv2TestStub()
    }

    private var resolver: ServerIdentityResolver {
        ServerIdentityResolver(httpClient: HTTPClient(session: stub.makeSession()))
    }

    func testIdentityProbeClassifiesEveryAnswer() async {
        stub.reply(.json(200, #"{"server_id":"  srv-1  "}"#))
        let identity = await resolver.probeIdentity(serverURL: serverURL)
        XCTAssertEqual(identity, .identity("srv-1"))
        XCTAssertEqual(stub.requestedPaths, [ServerIdentity.identityPath])

        stub.reply(.json(200, #"{"server_id":"srv-2"}"#))
        let fetched = await resolver.fetchServerIdentity(serverURL: serverURL)
        XCTAssertEqual(fetched, "srv-2")

        stub.reply(.json(200, #"{"server_id":"   "}"#))
        let blank = await resolver.probeIdentity(serverURL: serverURL)
        XCTAssertEqual(blank, .unreachable)
        let blankFetch = await resolver.fetchServerIdentity(serverURL: serverURL)
        XCTAssertNil(blankFetch)

        stub.reply(.text(404, "404 page not found\n", contentType: "text/plain; charset=utf-8"))
        let legacy = await resolver.probeIdentity(serverURL: serverURL)
        XCTAssertEqual(legacy, .unsupportedServer)

        stub.reply(.text(404, "<html>Not Found</html>", contentType: "text/html"))
        let otherNotFound = await resolver.probeIdentity(serverURL: serverURL)
        XCTAssertEqual(otherNotFound, .unreachable)

        stub.reply(.json(500, #"{"type":"about:blank","title":"t","status":500,"detail":"d"}"#))
        let serverError = await resolver.probeIdentity(serverURL: serverURL)
        XCTAssertEqual(serverError, .unreachable)

        stub.fail(.cannotConnectToHost)
        let offline = await resolver.probeIdentity(serverURL: serverURL)
        XCTAssertEqual(offline, .unreachable)
    }

    func testBrandingNameIsTrimmedOrAbsent() async {
        stub.reply(.json(200, #"{"server_name":"  Home Media  "}"#))
        let name = await resolver.fetchServerName(serverURL: serverURL)
        XCTAssertEqual(name, "Home Media")
        XCTAssertEqual(stub.requestedPaths, [ServerIdentity.brandingPath])

        stub.reply(.json(200, #"{"server_name":""}"#))
        let empty = await resolver.fetchServerName(serverURL: serverURL)
        XCTAssertNil(empty)

        stub.reply(.text(404, "404 page not found", contentType: "text/plain"))
        let missing = await resolver.fetchServerName(serverURL: serverURL)
        XCTAssertNil(missing)
    }

    func testConnectionsReadNeedsAnAvailableDocument() async throws {
        stub.reply(.json(200, """
        {"revision":"1","state":"available","allowed":true,"server_id":"srv-1",
         "current":{"kind":"public","provider":null},
         "endpoints":[
           {"kind":"public","url":"https://media.example/","state":"ok"},
           {"kind":"public","url":"https://media.example"},
           {"kind":"provider","url":"http://100.64.0.2:8096","provider":"tailscale","display_name":"Tailscale"},
           {"kind":"relay","url":"https://relay.example"},
           {"kind":"public","url":"  "}
         ]}
        """))
        let document = await resolver.fetchConnections(serverURL: serverURL, bearer: "token-1")
        let connections = try XCTUnwrap(document)
        XCTAssertEqual(stub.requests.first?.header("authorization"), "Bearer token-1")
        XCTAssertEqual(stub.requestedPaths, [ServerIdentity.connectionsPath])
        XCTAssertEqual(connections.current?.kind, "public")
        XCTAssertEqual(connections.usableEndpoints.map(\.url),
                       ["https://media.example", "http://100.64.0.2:8096"])
        XCTAssertEqual(connections.usableEndpoints.last?.kind, .provider)
        XCTAssertEqual(connections.usableEndpoints.last?.displayName, "Tailscale")

        stub.reply(.json(200, #"{"state":"disabled","server_id":"srv-1","endpoints":[]}"#))
        let disabled = await resolver.fetchConnections(serverURL: serverURL, bearer: "token-1")
        XCTAssertNil(disabled)

        stub.reply(.json(200, #"{"state":"available","allowed":false,"server_id":"srv-1","endpoints":[]}"#))
        let refused = await resolver.fetchConnections(serverURL: serverURL, bearer: "token-1")
        XCTAssertNil(refused)

        stub.reply(.json(401, #"{"type":"about:blank","title":"t","status":401,"detail":"d"}"#))
        let unauthorized = await resolver.fetchConnections(serverURL: serverURL, bearer: "bad")
        XCTAssertNil(unauthorized)
    }

    func testEndpointCodingAndHelp() throws {
        let decoded = try HTTPClient.makeJSONDecoder().decode([ServerEndpoint].self, from: Data("""
        [{"url":"https://a.example/","kind":"public"},
         {"url":"http://b.example","kind":"provider","provider":"tailscale","displayName":"Tailscale"},
         {"url":"https://c.example","kind":"mesh"}]
        """.utf8))
        XCTAssertEqual(decoded[0].url, "https://a.example")
        XCTAssertEqual(decoded[1].provider, "tailscale")
        XCTAssertEqual(decoded[2].kind, .public, "an unknown kind falls back to public")

        let roundTrip = try JSONDecoder().decode(ServerEndpoint.self, from: JSONEncoder().encode(decoded[1]))
        XCTAssertEqual(roundTrip, decoded[1])
        let bare = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded[0])) as? [String: Any])
        XCTAssertEqual(Set(bare.keys), ["url", "kind"])

        XCTAssertTrue(decoded[0].unreachableHelp(serverName: "Home").contains("at https://a.example"))
        XCTAssertTrue(decoded[1].unreachableHelp(serverName: "Home").contains("through Tailscale"))
        let unnamed = ServerEndpoint(url: "http://x.example", kind: .provider)
        XCTAssertTrue(unnamed.unreachableHelp(serverName: "Home").contains("its network provider"))
        XCTAssertNil(ServerIdentity.usable(nil))
        XCTAssertEqual(ServerIdentity.usable(" id "), "id")
    }
}
