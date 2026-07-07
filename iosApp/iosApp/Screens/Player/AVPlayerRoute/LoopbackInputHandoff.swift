import Foundation
import Libavformat

/// Cancellation flag for FFmpeg's interrupt callback. FFmpeg COPIES the
/// `AVIOInterruptCB` struct into nested contexts at open time (the http/tcp
/// URLContext and AVIOContext each hold their own copy), so the callback's
/// opaque pointer must outlive every owner of the AVFormatContext — pointing
/// it at the writer crashes on the first read after a demuxer handoff (the
/// retired writer deallocates; living-room SIGSEGV on seek). The token is
/// created once per fresh `avformat_open_input` and travels with the context
/// through every recycle; the adopting writer resets it and cancels it from
/// then on.
final class LoopbackInterruptToken {
    /// Max blocking-read park while the source proxy reports an origin
    /// outage. The view model's outage budget (90 s) tears playback down —
    /// and cancels this token — long before this backstop; it only exists so
    /// a ride-through whose owner died can't hold the mux thread forever.
    static let outageParkAllowanceSeconds: Double = 240

    private let lock = NSLock()
    private var cancelled = false
    /// Wall time the current bracketed blocking span started (0 = none).
    /// The interrupt callback enforces the span's allowance — this replaces
    /// the fixed avio `rw_timeout`, which cannot park through an outage.
    private var spanStartedAt: CFAbsoluteTime = 0
    private var spanAllowanceSeconds: Double = 0
    private var deadlineAborted = false
    /// Live query into the source proxy's outage state; when true, a
    /// blocking read is allowed to park up to `outageParkAllowanceSeconds`
    /// instead of its normal allowance. Called from FFmpeg's IO thread
    /// outside this token's lock (it takes the proxy's own lock).
    private var sourceOutageActive: (() -> Bool)?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Called by the adopting writer after a claim: the retiring writer's
    /// stop() cancelled the token; reads under the new owner must proceed.
    /// Clears deadline state and the outage provider — the adopter installs
    /// its own.
    func reset() {
        lock.lock()
        cancelled = false
        spanStartedAt = 0
        deadlineAborted = false
        sourceOutageActive = nil
        lock.unlock()
    }

    func setSourceOutageProvider(_ provider: (() -> Bool)?) {
        lock.lock()
        sourceOutageActive = provider
        lock.unlock()
    }

    /// Bracket a blocking FFmpeg call (read/open). The interrupt callback
    /// aborts the call once it exceeds `allowanceSeconds` — or the outage
    /// park allowance while the source reports an outage.
    func beginBlockingSpan(allowanceSeconds: Double) {
        lock.lock()
        spanStartedAt = CFAbsoluteTimeGetCurrent()
        spanAllowanceSeconds = allowanceSeconds
        deadlineAborted = false
        lock.unlock()
    }

    func endBlockingSpan() {
        lock.lock()
        spanStartedAt = 0
        lock.unlock()
    }

    /// Whether the last abort came from the span deadline (a wedged or
    /// outage-exhausted read) rather than cancellation. The mux loop uses
    /// this to classify the resulting AVERROR_EXIT as a source failure
    /// instead of a clean cancel.
    var didAbortOnDeadline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return deadlineAborted
    }

    /// The interrupt callback body. Kept on the token so the C callback
    /// stays a one-liner over the opaque pointer.
    func shouldInterrupt() -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            return true
        }
        let started = spanStartedAt
        let base = spanAllowanceSeconds
        let provider = sourceOutageActive
        lock.unlock()
        guard started > 0 else { return false }
        let allowance = provider?() == true
            ? max(base, Self.outageParkAllowanceSeconds)
            : base
        guard CFAbsoluteTimeGetCurrent() - started > allowance else { return false }
        lock.lock()
        deadlineAborted = true
        lock.unlock()
        return true
    }
}

/// Hands the open source `AVFormatContext` from a stopping VOD producer to
/// its restart replacement, so a seek-triggered producer swap skips
/// `avformat_open_input` + `find_stream_info` + the matroska cue warm
/// against the remote source (~1–1.5 s of every seek).
///
/// Thread contract: the retiring writer publishes from its mux queue during
/// teardown (interrupt callback already detached); the successor claims from
/// its own mux queue with a bounded wait. Exactly one side ends up owning
/// the context; an unclaimed published context is closed by `deinit`.
final class LoopbackInputHandoff {
    private let lock = NSCondition()
    private var context: UnsafeMutablePointer<AVFormatContext>?
    private var token: LoopbackInterruptToken?
    private var published = false
    private var abandoned = false

    deinit {
        print("[CMP-LIFE] deinit LoopbackInputHandoff hadContext=\(context != nil ? 1 : 0)")
        if context != nil {
            avformat_close_input(&context)
        }
    }

    /// Retiring writer: transfer ownership of the open input plus the
    /// interrupt token its nested I/O contexts point at. Closes the input
    /// immediately if the successor already gave up waiting.
    func publish(
        _ ctx: UnsafeMutablePointer<AVFormatContext>,
        token interruptToken: LoopbackInterruptToken
    ) {
        lock.lock()
        if abandoned {
            lock.unlock()
            var doomed: UnsafeMutablePointer<AVFormatContext>? = ctx
            avformat_close_input(&doomed)
            return
        }
        context = ctx
        token = interruptToken
        published = true
        lock.broadcast()
        lock.unlock()
    }

    /// Retiring writer: nothing will be published (input already closed or
    /// never opened). Wakes the successor so it opens fresh immediately
    /// instead of riding out its claim timeout.
    func cancelPublication() {
        lock.lock()
        abandoned = true
        lock.broadcast()
        lock.unlock()
    }

    /// Successor: wait up to `timeout` for the retiring producer's input.
    /// Returns nil (and releases the publisher to close the context itself)
    /// when the handoff is cancelled or the wait times out.
    func claim(
        timeout: TimeInterval
    ) -> (context: UnsafeMutablePointer<AVFormatContext>, token: LoopbackInterruptToken)? {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        while !published, !abandoned, Date() < deadline {
            lock.wait(until: deadline)
        }
        let claimedContext = context
        let claimedToken = token
        context = nil
        token = nil
        if claimedContext == nil {
            abandoned = true
        }
        lock.unlock()
        guard let claimedContext, let claimedToken else { return nil }
        return (claimedContext, claimedToken)
    }
}
