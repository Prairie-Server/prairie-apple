//
//  EndOfFileCoordinator.swift
//  Continuum (iOS + tvOS)
//

import Foundation

/// Thread-safe end-of-input/end-of-playback state for `PlayerCore`.
final class EndOfFileCoordinator {
    private let lock = NSLock()
    private var hasFiredEndOfFile = false
    private var reachedInputEndOfFile = false
    private var generation: UInt64 = 0

    /// Test-and-set for playback EOF so the public callback fires exactly once.
    @discardableResult
    func claimEndOfFile() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if hasFiredEndOfFile { return false }
        hasFiredEndOfFile = true
        return true
    }

    func markInputEndOfFile(generation expectedGeneration: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard expectedGeneration == generation else { return false }
        reachedInputEndOfFile = true
        return true
    }

    func hasReachedInputEndOfFile() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reachedInputEndOfFile
    }

    func currentGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        hasFiredEndOfFile = false
        reachedInputEndOfFile = false
        generation &+= 1
    }
}
