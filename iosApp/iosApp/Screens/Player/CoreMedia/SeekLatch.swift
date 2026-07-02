import Foundation

/// Latest-wins coalescing latch for seek targets.
///
/// A full `PlayerCore` seek cycle is expensive: queue drains, three worker
/// barriers, decoder + renderer flushes, and a preroll gate. Running one
/// cycle per scrub tick serializes seconds of churn on the control queue.
/// The latch collapses a burst into "newest target wins": every caller
/// `submit`s; the first submission after idle starts a worker, later
/// submissions overwrite the pending target. The worker loops `take()` until
/// empty, then must call `finish()` — which re-checks under the same lock so
/// a submit racing the final nil `take()` is handed to the still-running
/// worker instead of being stranded with no worker to serve it.
final class SeekLatch {
    private let lock = NSLock()
    private var pendingTarget: Double?
    private var workerActive = false

    /// Record `target` as the newest pending seek. Returns `true` when the
    /// caller must start a worker; `false` when an active worker will pick
    /// the target up.
    func submit(_ target: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pendingTarget = target
        if workerActive { return false }
        workerActive = true
        return true
    }

    /// Worker: claim the newest pending target, or nil when none is pending.
    /// Does not release ownership — that's `finish()`.
    func take() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let target = pendingTarget
        pendingTarget = nil
        return target
    }

    /// True when a target has been submitted and not yet taken. Cheap enough
    /// for mid-seek superseded checks.
    var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingTarget != nil
    }

    /// Worker: attempt to release ownership. If a submit raced in after the
    /// worker's last nil `take()`, ownership is retained and the raced-in
    /// target is returned — the worker must continue with it. Returns nil
    /// once ownership is actually released.
    func finish() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        if let target = pendingTarget {
            pendingTarget = nil
            return target
        }
        workerActive = false
        return nil
    }

    /// Drop any pending target and release ownership. Dispose-only: callers
    /// must guarantee no further submits race this (PlayerCore's `seek(to:)`
    /// guards on `isDisposed` before submitting).
    func abandon() {
        lock.lock()
        pendingTarget = nil
        workerActive = false
        lock.unlock()
    }
}
