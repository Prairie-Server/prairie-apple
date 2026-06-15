import Foundation

/// Computes the stable "Not Now" dismissal key for a discovered TV.
///
/// Keying on the TV's per-session nonce (`sid`) means a dismissal lasts only
/// until the TV restarts its pairing request (which yields a fresh `sid`); a
/// brief Bonjour flap keeps the same `sid` and stays dismissed. Falls back to
/// the device `id` for older TVs that don't advertise a nonce.
///
/// No platform guard so the command-line test can compile it directly; the
/// logic is pure and harmless on every target.
enum CompanionPairingDismissal {
    static func key(id: String, sid: String?) -> String {
        if let sid, !sid.isEmpty { return "\(id)#\(sid)" }
        return id
    }
}
