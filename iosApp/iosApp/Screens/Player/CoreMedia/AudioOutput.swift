import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation
import Libavutil
import os

struct NegotiatedAudioOutput {
    let sampleRate: Int32
    let channelCount: Int32
    let channelLayout: AVChannelLayout
    let formatDescription: CMAudioFormatDescription
    let audioFormat: AVAudioFormat
    let bytesPerSample: Int
    let layoutTag: AudioChannelLayoutTag
}

struct DecodedAudioChunk {
    let pts: CMTime
    let duration: CMTime
    let sampleRate: Int32
    let channelCount: Int32
    let frameCount: AVAudioFrameCount
    let bytesPerSample: Int
    let audioFormat: AVAudioFormat
    let planes: [Data]
}

/// Thin wrapper around `os_unfair_lock` for state shared between the
/// `AVAudioSourceNode` render callback (real-time audio thread) and the
/// enqueue/feed paths. `os_unfair_lock` is bounded-latency under contention
/// (single CAS, ~100 ns in the worst case) where `NSLock` can park the
/// caller for hundreds of microseconds — which would dropouts an audio
/// render slice. The render path is still not formally real-time safe (a
/// future SPSC ring buffer is the next step) but this caps the
/// pathological tail.
final class RealtimeAudioLock {
    private let pointer: UnsafeMutablePointer<os_unfair_lock_s>

    init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock_s())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    func lock() { os_unfair_lock_lock(pointer) }
    func unlock() { os_unfair_lock_unlock(pointer) }
}

final class AudioEngineAudioOutput {
    private struct RenderCursor {
        let pts: CMTime
        let sampleRate: Int32
        let frameCount: AVAudioFrameCount
        let readOffset: AVAudioFrameCount
    }

    private static let maxBufferedFrames = 192_000

    private let engine = AVAudioEngine()
    private let timePitch = AVAudioUnitTimePitch()
    private let stateLock = RealtimeAudioLock()

    private var sourceNode: AVAudioSourceNode?
    private var sourceNodeAudioFormat: AVAudioFormat?
    private var queuedChunks: [DecodedAudioChunk] = []
    private var currentChunk: DecodedAudioChunk?
    private var currentChunkReadOffset: AVAudioFrameCount = 0
    private var lastRenderCursor: RenderCursor?
    private var bufferedFrames = 0
    private var requestQueue: DispatchQueue?
    private var requestHandler: (() -> Void)?
    private var feedScheduled = false
    private var outputLatency: Double = 0

    private(set) var lastErrorDescription: String?

    var onRenderedTime: ((CMTime) -> Void)?

    /// Fires exactly once per `prepare`/`play` failure transition, after the
    /// failure has been recorded on `lastErrorDescription`. PlayerCore wires
    /// this into `reportError` so AVAudioEngine setup/start failures reach
    /// the VM (which can fall back to SiloPlayer or surface a user error)
    /// instead of only landing on a DIAG log line.
    var onFailure: ((String) -> Void)?

    init() {
        engine.attach(timePitch)
        timePitch.rate = 1.0
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
        if let audioUnit = engine.outputNode.audioUnit {
            addRenderNotify(audioUnit: audioUnit)
        }
    }

    var isReadyForMoreMediaData: Bool {
        stateLock.lock()
        let ready = bufferedFrames < Self.maxBufferedFrames
        stateLock.unlock()
        return ready
    }

    var bufferedDurationSeconds: Double {
        stateLock.lock()
        let frames = bufferedFrames
        let rate = sourceNodeAudioFormat?.sampleRate ?? 0
        stateLock.unlock()
        guard rate > 0 else { return 0 }
        return Double(frames) / rate
    }

    var statusCode: Int {
        stateLock.lock()
        let failed = lastErrorDescription != nil
        stateLock.unlock()
        if failed { return 2 }
        return engine.isRunning ? 1 : 0
    }

    func currentFormat() -> AVAudioFormat? {
        stateLock.lock()
        let format = sourceNodeAudioFormat
        stateLock.unlock()
        return format
    }

    func setRate(_ rate: Float) {
        timePitch.rate = rate
    }

    func prepare(audioFormat: AVAudioFormat) {
        stateLock.lock()
        let sameFormat = Self.formatMatches(sourceNodeAudioFormat, audioFormat)
        stateLock.unlock()
        if sameFormat { return }

        let wasRunning = engine.isRunning
        engine.pause()
        engine.stop()
        engine.reset()

        if let sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }

        let newSourceNode = AVAudioSourceNode(format: audioFormat) { [weak self] _, _, frameCount, audioBufferList in
            self?.render(
                ioData: UnsafeMutableAudioBufferListPointer(audioBufferList),
                frameCount: frameCount
            ) ?? noErr
        }

        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(
            Int(audioFormat.channelCount)
        )
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif

        var errorDescription: NSString?
        let prepared = AVAudioEngineExceptionCatcher.configure(
            engine,
            sourceNode: newSourceNode,
            timePitch: timePitch,
            format: audioFormat,
            errorDescription: &errorDescription
        )
        guard prepared else {
            if engine.attachedNodes.contains(where: { $0 === newSourceNode }) {
                engine.detach(newSourceNode)
            }
            engine.reset()
            stateLock.lock()
            sourceNode = nil
            sourceNodeAudioFormat = nil
            let wasFailed = lastErrorDescription != nil
            let message = (errorDescription as String?) ?? "AVAudioEngine graph setup failed"
            lastErrorDescription = message
            stateLock.unlock()
            if !wasFailed {
                onFailure?(message)
            }
            return
        }
        sourceNode = newSourceNode
        stateLock.lock()
        sourceNodeAudioFormat = audioFormat
        lastErrorDescription = nil
        stateLock.unlock()
        if wasRunning {
            play()
        }
    }

    func play() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                stateLock.lock()
                let wasFailed = lastErrorDescription != nil
                let message = error.localizedDescription
                lastErrorDescription = message
                stateLock.unlock()
                if !wasFailed {
                    onFailure?(message)
                }
            }
        }
        scheduleFeedIfNeeded()
    }

    func pause() {
        if engine.isRunning {
            engine.pause()
        }
    }

    func flush() {
        stateLock.lock()
        queuedChunks.removeAll(keepingCapacity: false)
        currentChunk = nil
        currentChunkReadOffset = 0
        bufferedFrames = 0
        lastRenderCursor = nil
        stateLock.unlock()
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    func stop() {
        stopRequestingMediaData()
        flush()
        engine.pause()
        engine.stop()
        engine.reset()
    }

    func stopRequestingMediaData() {
        stateLock.lock()
        requestQueue = nil
        requestHandler = nil
        feedScheduled = false
        stateLock.unlock()
    }

    func requestMediaDataWhenReady(
        on queue: DispatchQueue,
        handler: @escaping () -> Void
    ) {
        stateLock.lock()
        requestQueue = queue
        requestHandler = handler
        stateLock.unlock()
        scheduleFeedIfNeeded()
    }

    func nudgeRequestMediaDataWhenReady() {
        scheduleFeedIfNeeded()
    }

    func enqueue(_ chunk: DecodedAudioChunk) {
        if currentFormat().map({ !Self.formatMatches($0, chunk.audioFormat) }) ?? true {
            prepare(audioFormat: chunk.audioFormat)
        }
        stateLock.lock()
        lastErrorDescription = nil
        queuedChunks.append(chunk)
        bufferedFrames += Int(chunk.frameCount)
        stateLock.unlock()
    }

    private func render(
        ioData: UnsafeMutableAudioBufferListPointer,
        frameCount: AVAudioFrameCount
    ) -> OSStatus {
        guard let outputBuffer = ioData.first, outputBuffer.mData != nil else {
            return noErr
        }

        var writeOffsetBytes = 0
        var framesRemaining = Int(frameCount)
        var renderCursor: RenderCursor?

        while framesRemaining > 0 {
            stateLock.lock()
            if currentChunk == nil, !queuedChunks.isEmpty {
                currentChunk = queuedChunks.removeFirst()
                currentChunkReadOffset = 0
            }
            guard let chunk = currentChunk else {
                stateLock.unlock()
                break
            }

            let availableFrames = Int(chunk.frameCount - currentChunkReadOffset)
            let framesToCopy = min(framesRemaining, availableFrames)
            let sourceOffset = Int(currentChunkReadOffset) * chunk.bytesPerSample
            let byteCount = framesToCopy * chunk.bytesPerSample
            for planeIndex in 0..<min(ioData.count, chunk.planes.count) {
                guard let destination = ioData[planeIndex].mData else { continue }
                chunk.planes[planeIndex].withUnsafeBytes { rawBuffer in
                    guard let source = rawBuffer.baseAddress else { return }
                    destination.advanced(by: writeOffsetBytes).copyMemory(
                        from: source.advanced(by: sourceOffset),
                        byteCount: byteCount
                    )
                }
            }
            currentChunkReadOffset += AVAudioFrameCount(framesToCopy)
            bufferedFrames = max(0, bufferedFrames - framesToCopy)
            renderCursor = RenderCursor(
                pts: chunk.pts,
                sampleRate: chunk.sampleRate,
                frameCount: chunk.frameCount,
                readOffset: currentChunkReadOffset
            )
            if currentChunkReadOffset >= chunk.frameCount {
                currentChunk = nil
                currentChunkReadOffset = 0
            }
            stateLock.unlock()

            writeOffsetBytes += byteCount
            framesRemaining -= framesToCopy
        }

        if writeOffsetBytes < Int(outputBuffer.mDataByteSize) {
            for index in 0..<ioData.count {
                if let bufferData = ioData[index].mData {
                    memset(
                        bufferData.advanced(by: writeOffsetBytes),
                        0,
                        Int(ioData[index].mDataByteSize) - writeOffsetBytes
                    )
                }
            }
        }

        stateLock.lock()
        lastRenderCursor = renderCursor
        stateLock.unlock()

        scheduleFeedIfNeeded()
        return noErr
    }

    private func scheduleFeedIfNeeded() {
        stateLock.lock()
        guard bufferedFrames < Self.maxBufferedFrames,
              let queue = requestQueue,
              let handler = requestHandler,
              !feedScheduled
        else {
            stateLock.unlock()
            return
        }
        feedScheduled = true
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.feedScheduled = false
            let liveHandler = self.requestHandler
            let ready = self.bufferedFrames < Self.maxBufferedFrames
            self.stateLock.unlock()
            guard ready else { return }
            (liveHandler ?? handler)()
        }
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, _, _, _, _ in
            let `self` = Unmanaged<AudioEngineAudioOutput>.fromOpaque(refCon).takeUnretainedValue()
            if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                self.handlePostRender()
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func handlePostRender() {
        stateLock.lock()
        let cursor = lastRenderCursor
        stateLock.unlock()
        guard let cursor, cursor.sampleRate > 0 else { return }

        var renderedTime = cursor.pts + CMTime(
            value: CMTimeValue(cursor.readOffset),
            timescale: CMTimeScale(cursor.sampleRate)
        )
        if outputLatency > 0 {
            renderedTime = renderedTime - CMTime(
                seconds: outputLatency,
                preferredTimescale: max(renderedTime.timescale, 600)
            )
        }
        onRenderedTime?(renderedTime)
    }

    private static func formatMatches(_ lhs: AVAudioFormat?, _ rhs: AVAudioFormat) -> Bool {
        guard let lhs else { return false }
        return lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
