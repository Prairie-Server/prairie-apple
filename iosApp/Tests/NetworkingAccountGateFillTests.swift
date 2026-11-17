import Foundation
import XCTest
@testable import Prairie

/// Coverage for the account, migration, merge, and login-session-proof
/// paths of `Networking/`. Server ids and account ids are unique per test;
/// anything that must touch `SharedDefaults.shared` or the downloads root is
/// removed again in `tearDown`.
final class NetworkingAccountGateFillTests: XCTestCase {
    private static let proofsKey = "serverMerge.proofs.v1"

    private var tags: [String] = []
    private var savedProofs: Data?

    override func setUp() {
        super.setUp()
        tags = []
        savedProofs = SharedDefaults.shared.data(forKey: Self.proofsKey)
    }

    override func tearDown() {
        let shared = SharedDefaults.shared
        for key in shared.allKeys where tags.contains(where: { key.contains($0) }) {
            shared.removeObject(forKey: key)
        }
        if let savedProofs {
            shared.set(savedProofs, forKey: Self.proofsKey)
        } else {
            shared.removeObject(forKey: Self.proofsKey)
        }
        let root = DownloadFilePaths.rootDirectory()
        for tag in tags {
            try? FileManager.default.removeItem(at: DownloadFilePaths.serverPath(serverId: tag, root: root))
        }
        tags = []
        super.tearDown()
    }

    // MARK: - Helpers

    private func tag() -> String {
        let value = "gf" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        tags.append(value)
        return value
    }

    private func makeDefaults() throws -> SharedDefaults {
        let name = "NetworkingAccountGateFillTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return SharedDefaults(suite: suite, standard: suite)
    }

    private func makeKeychain() -> SharedKeychain {
        SharedKeychain.inMemory(service: "NetworkingAccountGateFillTests.\(UUID().uuidString)")
    }

    private func makeAccount(server: String, id: String = UUID().uuidString) -> Account {
        Account(localAccountId: id, serverId: server, origin: "https://\(server).example",
                accessToken: "access", refreshToken: "refresh", epoch: UUID())
    }

    private func entry(_ id: String) -> ServerEntry {
        ServerEntry(id: id, url: "https://\(id).example", fetchedName: nil, lastUsedAt: Date())
    }

    private func makeFile(_ directory: URL, _ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - LoginSessionProof.check

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var cursors: [String?] = []
        func record(_ cursor: String?) {
            lock.lock()
            cursors.append(cursor)
            lock.unlock()
        }
        var seen: [String?] {
            lock.lock()
            defer { lock.unlock() }
            return cursors
        }
    }

    private func page(current: String?, items: [(String, Bool)] = [], hasMore: Bool? = nil,
                      next: String? = nil) throws -> APIv2LoginSessionPage {
        var object: [String: Any] = [
            "items": items.map { (item: (String, Bool)) -> [String: Any] in ["id": item.0, "current": item.1] },
        ]
        if let current { object["current_session"] = ["id": current, "current": true] as [String: Any] }
        if let hasMore {
            var paging: [String: Any] = ["has_more": hasMore]
            if let next { paging["next_cursor"] = next }
            object["page"] = paging
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(APIv2LoginSessionPage.self, from: data)
    }

    func testProofUnavailableWhenOwnSessionCannotBeRead() async throws {
        let holder = try page(current: "H", items: [("S", false)], hasMore: false)
        let thrown = await LoginSessionProof.check(
            own: { _ in throw URLError(.badServerResponse) },
            holder: { _ in holder }
        )
        XCTAssertEqual(thrown, .unavailable)
        let none = try page(current: nil)
        let missing = await LoginSessionProof.check(own: { _ in none }, holder: { _ in holder })
        XCTAssertEqual(missing, .unavailable)
        let blank = try page(current: "")
        let empty = await LoginSessionProof.check(own: { _ in blank }, holder: { _ in holder })
        XCTAssertEqual(empty, .unavailable)
    }

    func testProofProvenWhenHolderListsTheOwnSession() async throws {
        let own = try page(current: "S")
        let holder = try page(current: "H", items: [("other", false), ("S", false)], hasMore: false)
        let outcome = await LoginSessionProof.check(own: { _ in own }, holder: { _ in holder })
        XCTAssertEqual(outcome, .proven)
    }

    func testProofDisprovenWhenHolderDoesNotKnowTheSession() async throws {
        let own = try page(current: "S")
        let unrelated = try page(current: "H", items: [("other", false)], hasMore: false)
        let disproven = await LoginSessionProof.check(own: { _ in own }, holder: { _ in unrelated })
        XCTAssertEqual(disproven, .disproven)
        // The holder's own session never counts, and no paging info ends the search.
        let holdersOwn = try page(current: "H", items: [("S", true)])
        let ownSession = await LoginSessionProof.check(own: { _ in own }, holder: { _ in holdersOwn })
        XCTAssertEqual(ownSession, .disproven)
        // More pages claimed but no cursor to follow.
        let noCursor = try page(current: "H", items: [], hasMore: true)
        let cursorless = await LoginSessionProof.check(own: { _ in own }, holder: { _ in noCursor })
        XCTAssertEqual(cursorless, .disproven)
        // A cursor with nothing more behind it.
        let finished = try page(current: "H", items: [], hasMore: false, next: "c")
        let done = await LoginSessionProof.check(own: { _ in own }, holder: { _ in finished })
        XCTAssertEqual(done, .disproven)
    }

    func testProofFollowsCursorsToALaterPage() async throws {
        let own = try page(current: "S")
        let first = try page(current: "H", items: [("a", false)], hasMore: true, next: "c2")
        let second = try page(current: "H", items: [("S", false)], hasMore: false)
        let recorder = Recorder()
        let outcome = await LoginSessionProof.check(
            own: { _ in own },
            holder: { cursor in
                recorder.record(cursor)
                return cursor == nil ? first : second
            }
        )
        XCTAssertEqual(outcome, .proven)
        XCTAssertEqual(recorder.seen, [nil, "c2"])
    }

    func testProofUnavailableWhenHolderFailsOrNeverEnds() async throws {
        let own = try page(current: "S")
        let failing = await LoginSessionProof.check(own: { _ in own }, holder: { _ in throw URLError(.timedOut) })
        XCTAssertEqual(failing, .unavailable)

        let endless = try page(current: "H", items: [("a", false)], hasMore: true, next: "again")
        let recorder = Recorder()
        let outcome = await LoginSessionProof.check(own: { _ in own }, holder: { cursor in
            recorder.record(cursor)
            return endless
        })
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(recorder.seen.count, LoginSessionProof.maximumSessionPages)
    }

    // MARK: - Loopback server (the merge proof reads through its own URLSession)

    private final class LoopbackServer: @unchecked Sendable {
        typealias Responder = @Sendable (String) -> (status: Int, body: String)

        let port: Int
        private let listener: Int32
        private let responder: Responder
        private let lock = NSLock()
        private var stopped = false
        private var received: [String] = []

        init?(responder: @escaping Responder) {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            var enable: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bound = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0, Darwin.listen(descriptor, 8) == 0 else {
                close(descriptor)
                return nil
            }
            var actual = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &actual) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(descriptor, $0, &length)
                }
            }
            guard named == 0 else {
                close(descriptor)
                return nil
            }
            self.port = Int(UInt16(bigEndian: actual.sin_port))
            self.listener = descriptor
            self.responder = responder
            Thread.detachNewThread { [self] in self.serve() }
        }

        var origin: String { "http://127.0.0.1:\(port)" }

        var requests: [String] {
            lock.lock()
            defer { lock.unlock() }
            return received
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
        }

        private func serve() {
            while true {
                lock.lock()
                let done = stopped
                lock.unlock()
                if done { break }
                var watch = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&watch, 1, 50) > 0 else { continue }
                let client = accept(listener, nil, nil)
                if client < 0 { continue }
                handle(client)
            }
            close(listener)
        }

        private func handle(_ client: Int32) {
            var enable: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size))
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            let capacity = buffer.count
            for _ in 0..<16 {
                var watch = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
                guard poll(&watch, 1, 1000) > 0 else { break }
                let count = recv(client, &buffer, capacity, 0)
                if count <= 0 { break }
                data.append(contentsOf: buffer[0..<count])
                if String(decoding: data, as: UTF8.self).contains("\r\n\r\n") { break }
            }
            let request = String(decoding: data, as: UTF8.self)
            lock.lock()
            received.append(request)
            lock.unlock()
            let reply = responder(request)
            let payload = Data(reply.body.utf8)
            let head = "HTTP/1.1 \(reply.status) Reply\r\nContent-Type: application/json\r\n"
                + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            var out = Data(head.utf8)
            out.append(payload)
            out.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var sent = 0
                while sent < raw.count {
                    let written = send(client, base + sent, raw.count - sent, 0)
                    if written <= 0 { break }
                    sent += written
                }
            }
            close(client)
        }
    }

    private static let ownJSON = #"{"current_session":{"id":"S1","current":true},"items":[],"page":{"has_more":false}}"#
    private static let provenJSON =
        #"{"current_session":{"id":"H1","current":true},"items":[{"id":"S1","current":false}],"page":{"has_more":false}}"#
    private static let unrelatedJSON =
        #"{"current_session":{"id":"H1","current":true},"items":[{"id":"S2","current":true}],"page":{"has_more":false}}"#

    private struct ProveHarness {
        let accounts: AccountStore
        let http: HTTPClient
        let left: Account
        let right: Account
        var leftId: String { left.serverId }
        var rightId: String { right.serverId }
    }

    private func startServer(status: Int = 200, body: String) throws -> LoopbackServer {
        guard let server = LoopbackServer(responder: { _ in (status, body) }) else {
            throw XCTSkip("A loopback listener is not available here.")
        }
        addTeardownBlock { server.stop() }
        return server
    }

    private func proveHarness(left: LoopbackServer, right: LoopbackServer,
                              leftUser: String = "u1", rightUser: String = "u1") throws -> ProveHarness {
        let keychain = makeKeychain()
        let defaults = try makeDefaults()
        let accounts = AccountStore(keychain: keychain, defaults: defaults)
        let leftId = ServerRegistry.serverId(for: left.origin)
        let rightId = ServerRegistry.serverId(for: right.origin)
        let leftAccount = try accounts.saveSignIn(
            serverId: leftId, origin: left.origin, serverUserId: leftUser, username: nil,
            accessToken: "tokA", refreshToken: "refreshA", replacingOtherAccounts: false).account
        let rightAccount = try accounts.saveSignIn(
            serverId: rightId, origin: right.origin, serverUserId: rightUser, username: nil,
            accessToken: "tokB", refreshToken: "refreshB", replacingOtherAccounts: false).account
        let tokens = TokenStore(keychain: keychain, defaults: defaults, accounts: accounts)
        let http = HTTPClient(session: URLSession(configuration: .ephemeral), tokenStore: tokens)
        return ProveHarness(accounts: accounts, http: http, left: leftAccount, right: rightAccount)
    }

    // MARK: - ServerMerge.prove

    func testProveStoresProofWhenHolderListsTheSession() async throws {
        let own = try startServer(body: Self.ownJSON)
        let holder = try startServer(body: Self.provenJSON)
        let harness = try proveHarness(left: own, right: holder)

        let outcome = await ServerMerge.prove(harness.leftId, harness.rightId, accounts: harness.accounts, http: harness.http)
        XCTAssertEqual(outcome, .proven)
        let saved = try harness.accounts.accounts()
        XCTAssertEqual(ServerMerge.cachedProof(harness.leftId, harness.rightId, accounts: saved), .proven)
        XCTAssertEqual(ServerMerge.cachedProof(harness.rightId, harness.leftId, accounts: saved), .proven)

        // Each address saw only its own account's bearer.
        XCTAssertTrue(own.requests.contains { $0.contains("/api/v2/auth/sessions") && $0.contains("Bearer tokA") })
        XCTAssertFalse(own.requests.contains { $0.contains("tokB") })
        XCTAssertTrue(holder.requests.contains { $0.contains("/api/v2/auth/sessions") && $0.contains("Bearer tokB") })
        XCTAssertFalse(holder.requests.contains { $0.contains("tokA") })
    }

    func testProveStoresDisproofWhenHolderDoesNotKnowTheSession() async throws {
        let own = try startServer(body: Self.ownJSON)
        let holder = try startServer(body: Self.unrelatedJSON)
        let harness = try proveHarness(left: own, right: holder)

        let outcome = await ServerMerge.prove(harness.leftId, harness.rightId, accounts: harness.accounts, http: harness.http)
        XCTAssertEqual(outcome, .disproven)
        let saved = try harness.accounts.accounts()
        XCTAssertEqual(ServerMerge.cachedProof(harness.leftId, harness.rightId, accounts: saved), .disproven)
        // A disproof holds only while both compared sessions are saved.
        let withoutHolder = saved.filter { $0.localAccountId != harness.right.localAccountId }
        XCTAssertNil(ServerMerge.cachedProof(harness.leftId, harness.rightId, accounts: withoutHolder))
    }

    func testProveGivesNothingWhenAddressAnswersWithAnError() async throws {
        let own = try startServer(status: 500, body: "{}")
        let holder = try startServer(body: Self.provenJSON)
        let harness = try proveHarness(left: own, right: holder)

        let outcome = await ServerMerge.prove(harness.leftId, harness.rightId, accounts: harness.accounts, http: harness.http)
        XCTAssertNil(outcome)
        let saved = try harness.accounts.accounts()
        XCTAssertNil(ServerMerge.cachedProof(harness.leftId, harness.rightId, accounts: saved))
        XCTAssertFalse(own.requests.isEmpty)
    }

    func testProveSkipsPairsWithoutASharedUserOrAMatchingAddress() async throws {
        let own = try startServer(body: Self.ownJSON)
        let holder = try startServer(body: Self.provenJSON)
        let different = try proveHarness(left: own, right: holder, leftUser: "u1", rightUser: "u2")
        let noUser = await ServerMerge.prove(different.leftId, different.rightId, accounts: different.accounts,
                                             http: different.http)
        XCTAssertNil(noUser)
        XCTAssertTrue(own.requests.isEmpty)
        XCTAssertTrue(holder.requests.isEmpty)

        // Accounts bound to an address their server id does not name never ask.
        let keychain = makeKeychain()
        let defaults = try makeDefaults()
        let accounts = AccountStore(keychain: keychain, defaults: defaults)
        let first = tag(), second = tag()
        for id in [first, second] {
            _ = try accounts.saveSignIn(serverId: id, origin: "https://\(id).example", serverUserId: "u1", username: nil,
                                        accessToken: "tok", refreshToken: "refresh", replacingOtherAccounts: false)
        }
        let tokens = TokenStore(keychain: keychain, defaults: defaults, accounts: accounts)
        let http = HTTPClient(session: URLSession(configuration: .ephemeral), tokenStore: tokens)
        let unbound = await ServerMerge.prove(first, second, accounts: accounts, http: http)
        XCTAssertNil(unbound)
        let missing = await ServerMerge.prove(tag(), tag(), accounts: accounts, http: http)
        XCTAssertNil(missing)
    }

    // MARK: - ServerMerge.moveLocalData

    func testMoveLocalDataMovesDownloadsAndKeysOfMovedAndRemovedAccounts() throws {
        let dropped = tag(), survivor = tag()
        let moved = makeAccount(server: dropped)
        let removedAccount = makeAccount(server: dropped)
        let kept = UUID().uuidString
        let merge = AccountServerMerge(
            droppedServerId: dropped, survivorServerId: survivor, moved: [moved],
            removed: [AccountServerMerge.Removal(account: removedAccount, keptLocalAccountId: kept)],
            legacyDataOwner: nil
        )
        let root = DownloadFilePaths.rootDirectory()
        let movedSource = DownloadFilePaths.accountPath(serverId: dropped, localAccountId: moved.localAccountId, root: root)
        let removedSource = DownloadFilePaths.accountPath(serverId: dropped, localAccountId: removedAccount.localAccountId, root: root)
        try makeFile(movedSource.appendingPathComponent("default"), "moved.txt", "moved")
        try makeFile(removedSource.appendingPathComponent("default"), "removed.txt", "removed")

        let shared = SharedDefaults.shared
        let marker = AccountScopedKeyAdoption.versionMarker
        let oldKey = "tp.\(marker).\(dropped).\(moved.localAccountId).default"
        let newKey = "tp.\(marker).\(survivor).\(moved.localAccountId).default"
        let keptOld = "tp.\(marker).\(dropped).\(moved.localAccountId).keep"
        let keptNew = "tp.\(marker).\(survivor).\(moved.localAccountId).keep"
        shared.set("moved value", forKey: oldKey)
        shared.set("lost value", forKey: keptOld)
        shared.set("kept value", forKey: keptNew)

        XCTAssertTrue(ServerMerge.moveLocalData(merge, from: entry(dropped), to: entry(survivor)))

        let movedTarget = DownloadFilePaths.accountPath(serverId: survivor, localAccountId: moved.localAccountId, root: root)
        let removedTarget = DownloadFilePaths.accountPath(serverId: survivor, localAccountId: kept, root: root)
        XCTAssertTrue(exists(movedTarget.appendingPathComponent("default/moved.txt")))
        XCTAssertFalse(exists(movedSource))
        XCTAssertTrue(exists(removedTarget.appendingPathComponent("default/removed.txt")))
        XCTAssertFalse(exists(removedSource))

        XCTAssertEqual(shared.string(forKey: newKey), "moved value")
        XCTAssertFalse(shared.containsObject(forKey: oldKey))
        // A key the survivor already has keeps its value, and the old one stays.
        XCTAssertEqual(shared.string(forKey: keptNew), "kept value")
        XCTAssertEqual(shared.string(forKey: keptOld), "lost value")
    }

    func testMoveLocalDataGivesLegacyDownloadsAndKeysToTheOwner() throws {
        let dropped = tag(), survivor = tag()
        let owner = makeAccount(server: dropped)
        let merge = AccountServerMerge(
            droppedServerId: dropped, survivorServerId: survivor, moved: [owner], removed: [],
            legacyDataOwner: owner.localAccountId
        )
        let root = DownloadFilePaths.rootDirectory()
        let legacyScope = DownloadFilePaths.serverPath(serverId: dropped, root: root).appendingPathComponent("default")
        try makeFile(legacyScope, "old.txt", "old")

        let shared = SharedDefaults.shared
        let prefix = try XCTUnwrap(AccountLocalData.legacyKeyPrefixes.first)
        let marker = AccountScopedKeyAdoption.versionMarker
        shared.set("legacy value", forKey: "\(prefix).\(dropped).default")

        XCTAssertTrue(ServerMerge.moveLocalData(merge, from: entry(dropped), to: entry(survivor)))

        let target = DownloadFilePaths.accountPath(serverId: survivor, localAccountId: owner.localAccountId, root: root)
        XCTAssertTrue(exists(target.appendingPathComponent("default/old.txt")))
        let adopted = "\(prefix).\(marker).\(survivor).\(owner.localAccountId).default"
        XCTAssertEqual(shared.string(forKey: adopted), "legacy value")
        XCTAssertFalse(shared.containsObject(forKey: "\(prefix).\(dropped).default"))
    }

    func testMoveLocalDataReportsDownloadsThatCannotMerge() throws {
        let dropped = tag(), survivor = tag()
        let moved = makeAccount(server: dropped)
        let merge = AccountServerMerge(
            droppedServerId: dropped, survivorServerId: survivor, moved: [moved], removed: [], legacyDataOwner: nil
        )
        let root = DownloadFilePaths.rootDirectory()
        let source = DownloadFilePaths.accountPath(serverId: dropped, localAccountId: moved.localAccountId, root: root)
        let target = DownloadFilePaths.accountPath(serverId: survivor, localAccountId: moved.localAccountId, root: root)
        try makeFile(source.appendingPathComponent("default"), DownloadFilePaths.storeFileName, "not json")
        try makeFile(target.appendingPathComponent("default"), DownloadFilePaths.storeFileName, "not json either")

        XCTAssertFalse(ServerMerge.moveLocalData(merge, from: entry(dropped), to: entry(survivor)))
        // Nothing was deleted: the next launch retries.
        XCTAssertTrue(exists(source.appendingPathComponent("default/\(DownloadFilePaths.storeFileName)")))
        XCTAssertTrue(exists(target.appendingPathComponent("default/\(DownloadFilePaths.storeFileName)")))
    }

    // MARK: - ServerMerge.removeLeftovers

    @MainActor
    func testRemoveLeftoversPurgesRemovedAccountsAndEmptyServerDirectory() async throws {
        let dropped = tag(), survivor = tag()
        let removedAccount = makeAccount(server: dropped)
        let merge = AccountServerMerge(
            droppedServerId: dropped, survivorServerId: survivor, moved: [],
            removed: [AccountServerMerge.Removal(account: removedAccount, keptLocalAccountId: UUID().uuidString)],
            legacyDataOwner: nil
        )
        let shared = SharedDefaults.shared
        let key = "tp.\(AccountScopedKeyAdoption.versionMarker).\(dropped).\(removedAccount.localAccountId).default"
        shared.set("value", forKey: key)
        let directory = DownloadFilePaths.serverPath(serverId: dropped, root: DownloadFilePaths.rootDirectory())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        ServerMerge.removeLeftovers(merge, from: entry(dropped), stillSaved: [])

        XCTAssertFalse(exists(directory))
        var attempts = 0
        while shared.containsObject(forKey: key), attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        XCTAssertFalse(shared.containsObject(forKey: key))
    }

    // MARK: - AccountLocalData

    func testAdoptedAccountScopedKeyUsesTheAccountKey() throws {
        let defaults = try makeDefaults()
        let serverId = tag()
        let account = UUID().uuidString
        let identity = HTTPRequestIdentity(serverId: serverId, serverURL: "https://\(serverId).example",
                                           profileId: "default", clientFamily: "test", localAccountId: account)
        let expected = identity.accountScopedKey("tp", suffix: "tail")
        XCTAssertTrue(expected.contains(".\(AccountScopedKeyAdoption.versionMarker).\(serverId).\(account)."))
        // A value already under the account's key needs no look at who owned the old data.
        defaults.set("kept", forKey: expected)
        XCTAssertEqual(identity.adoptedAccountScopedKey("tp", suffix: "tail", defaults: defaults), expected)

        let anonymous = HTTPRequestIdentity(serverId: serverId, serverURL: "https://\(serverId).example",
                                            profileId: "default", clientFamily: "test")
        XCTAssertEqual(anonymous.adoptedAccountScopedKey("tp", defaults: defaults), anonymous.accountScopedKey("tp"))
    }

    @MainActor
    func testPurgeRemovesOnlyTheAccountsKeysAndOptionallyLegacyOnes() throws {
        let serverId = tag()
        let account = UUID().uuidString, other = UUID().uuidString
        let prefix = try XCTUnwrap(AccountLocalData.legacyKeyPrefixes.first)
        let marker = AccountScopedKeyAdoption.versionMarker
        let shared = SharedDefaults.shared
        let own = "tp.\(marker).\(serverId).\(account).default"
        let theirs = "tp.\(marker).\(serverId).\(other).default"
        let legacy = "\(prefix).\(serverId).default"
        shared.set("a", forKey: own)
        shared.set("b", forKey: theirs)
        shared.set("c", forKey: legacy)

        AccountLocalData.purge(localAccountId: account, serverId: serverId, ownedLegacyData: false)
        XCTAssertFalse(shared.containsObject(forKey: own))
        XCTAssertTrue(shared.containsObject(forKey: theirs))
        XCTAssertTrue(shared.containsObject(forKey: legacy))

        AccountLocalData.purge(localAccountId: account, serverId: serverId, ownedLegacyData: true)
        XCTAssertFalse(shared.containsObject(forKey: legacy))
        XCTAssertTrue(shared.containsObject(forKey: theirs))

        // Without an answer, the published owner of the server's old data decides.
        shared.set("c", forKey: legacy)
        LegacyLocalDataOwner.publish([serverId: account])
        AccountLocalData.purge(localAccountId: account, serverId: serverId)
        XCTAssertFalse(shared.containsObject(forKey: legacy))
        LegacyLocalDataOwner.publish([:])

        // A malformed scope is refused and nothing goes.
        shared.set("c", forKey: legacy)
        AccountLocalData.purge(localAccountId: "not-a-uuid", serverId: serverId, ownedLegacyData: true)
        AccountLocalData.purge(localAccountId: account, serverId: "a.b", ownedLegacyData: true)
        XCTAssertTrue(shared.containsObject(forKey: legacy))
    }

    // MARK: - AccountMigration

    private func canonicalRecord(origin: String, access: String = "access", refresh: String = "refresh",
                                 accountID: String? = "42", epoch: UUID = UUID()) throws -> String {
        let session = CanonicalAccountSession(version: 1, signedOut: false, origin: origin, accountID: accountID,
                                              epoch: epoch, accessToken: access, refreshToken: refresh)
        return String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
    }

    func testMigrationDefersWhenTheAccountIndexIsUnreadable() throws {
        let defaults = try makeDefaults()
        let accountsKeychain = makeKeychain()
        let accounts = AccountStore(keychain: accountsKeychain, defaults: defaults)
        accountsKeychain.memoryStore?.failReads = true
        let migration = AccountMigration(keychain: makeKeychain(), accounts: accounts)
        XCTAssertEqual(migration.runIfNeeded(servers: [], serverListIsComplete: true), .deferred)
    }

    func testMigrationDefersWhenASavedSessionIsUnreadable() throws {
        let defaults = try makeDefaults()
        let accounts = AccountStore(keychain: makeKeychain(), defaults: defaults)
        let legacyKeychain = makeKeychain()
        legacyKeychain.memoryStore?.failReads = true
        let migration = AccountMigration(keychain: legacyKeychain, accounts: accounts)
        let outcome = migration.runIfNeeded(servers: [(id: "s1", url: "https://s1.example")], serverListIsComplete: true)
        XCTAssertEqual(outcome, .deferred)
        XCTAssertNil(try accounts.loadIndex())
    }

    func testMigrationDefersWhenTheIndexCannotBeSaved() throws {
        let defaults = try makeDefaults()
        let accountsKeychain = makeKeychain()
        let accounts = AccountStore(keychain: accountsKeychain, defaults: defaults)
        accountsKeychain.memoryStore?.failWrites = true
        let migration = AccountMigration(keychain: makeKeychain(), accounts: accounts)
        XCTAssertEqual(migration.runIfNeeded(servers: [], serverListIsComplete: true), .deferred)
    }

    func testMigrationCarriesOverOnlyUsableRecords() throws {
        let defaults = try makeDefaults()
        let keychain = makeKeychain()
        let accounts = AccountStore(keychain: makeKeychain(), defaults: defaults)
        let slots = keychain.withAudience(.userIndependent)
        let epoch = UUID()

        // A record that does not decode is skipped.
        XCTAssertTrue(slots.set("{ not json", for: AccountSessionPersistence.recordKey("garbled")))
        // A marker without a record is a signed-out server.
        XCTAssertTrue(slots.set("1", for: AccountSessionPersistence.markerKey("signedout")))
        // A record bound to another address is not carried over.
        XCTAssertTrue(slots.set(try canonicalRecord(origin: "https://elsewhere.example"),
                                for: AccountSessionPersistence.recordKey("foreign")))
        // A record for this address becomes an account.
        XCTAssertTrue(slots.set(try canonicalRecord(origin: "https://good.example/", access: "tokenA", refresh: "tokenR",
                                                    accountID: "42", epoch: epoch),
                                for: AccountSessionPersistence.recordKey("good")))

        let migration = AccountMigration(keychain: keychain, accounts: accounts)
        let outcome = migration.runIfNeeded(
            servers: [
                (id: "garbled", url: "https://garbled.example"),
                (id: "signedout", url: "https://signedout.example"),
                (id: "foreign", url: "https://foreign.example"),
                (id: "good", url: "https://good.example"),
                (id: "good", url: "https://good.example"),
                (id: "", url: "https://empty.example"),
            ],
            serverListIsComplete: true
        )
        XCTAssertEqual(outcome, .migrated(accounts: 1))

        let saved = try accounts.accounts()
        XCTAssertEqual(saved.count, 1)
        let account = try XCTUnwrap(saved.first)
        XCTAssertEqual(account.serverId, "good")
        XCTAssertEqual(account.origin, "https://good.example")
        XCTAssertEqual(account.serverUserId, "42")
        XCTAssertEqual(account.accessToken, "tokenA")
        XCTAssertEqual(account.refreshToken, "tokenR")
        XCTAssertEqual(account.epoch, epoch)
        // The old slots of every listed server are gone once the index is written.
        XCTAssertNil(try slots.getChecked(AccountSessionPersistence.recordKey("good")))
        XCTAssertNil(try slots.getChecked(AccountSessionPersistence.recordKey("garbled")))
        XCTAssertEqual(migration.runIfNeeded(servers: [], serverListIsComplete: true), .notNeeded)
    }

    func testMigrationRetriesCleanupAndToleratesAFailureToRecordIt() throws {
        let defaults = try makeDefaults()
        let accountsKeychain = makeKeychain()
        let accounts = AccountStore(keychain: accountsKeychain, defaults: defaults)
        let keychain = makeKeychain()
        let slots = keychain.withAudience(.userIndependent)
        let serverId = "s1id"
        // A record that never migrates, and old slots whose deletion can be seen succeed.
        XCTAssertTrue(slots.set("{ not json", for: AccountSessionPersistence.recordKey(serverId)))
        XCTAssertTrue(slots.set("1", for: AccountSessionPersistence.markerKey(serverId)))
        XCTAssertTrue(slots.set("a", for: SharedStorage.accessTokenAccount(for: serverId)))
        XCTAssertTrue(slots.set("r", for: SharedStorage.refreshTokenAccount(for: serverId)))
        XCTAssertTrue(slots.set(UUID().uuidString, for: SharedStorage.accountEpochAccount(for: serverId)))
        let migration = AccountMigration(keychain: keychain, accounts: accounts)

        keychain.memoryStore?.failDeletes = true
        let first = migration.runIfNeeded(servers: [(id: serverId, url: "https://s1.example")], serverListIsComplete: true)
        XCTAssertEqual(first, .migrated(accounts: 0))
        XCTAssertEqual(try accounts.loadIndex()?.pendingLegacyCleanup, [serverId])

        // The deletion now works, but recording it does not: the run still ends cleanly.
        keychain.memoryStore?.failDeletes = false
        accountsKeychain.memoryStore?.failWrites = true
        XCTAssertEqual(migration.runIfNeeded(servers: [], serverListIsComplete: true), .notNeeded)
        accountsKeychain.memoryStore?.failWrites = false
        XCTAssertEqual(try accounts.loadIndex()?.pendingLegacyCleanup, [serverId])
    }

    func testAdoptingUserStateStaysIncompleteWhileAProofSlotIsUnreadable() throws {
        let defaults = try makeDefaults()
        let accounts = AccountStore(keychain: makeKeychain(), defaults: defaults)
        let account = makeAccount(server: "server")
        _ = try accounts.commitMigration([account], pendingLegacyCleanup: [])
        let unreadable = makeKeychain()
        unreadable.memoryStore?.failReads = true
        let migration = AccountMigration(keychain: unreadable, accounts: accounts)

        migration.adoptCurrentUserState(launchPreferences: ProfileLaunchPreferences(defaults: defaults), defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: SharedStorage.accountUserStateAdoptedKey))
    }
}
