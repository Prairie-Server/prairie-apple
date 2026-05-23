//
//  EmbeddedSubtitlePipeline.swift
//  Continuum (iOS + tvOS)
//

import Foundation
import Libavcodec
import Libavformat
import Libavutil
import OSLog

/// Owns FFmpeg subtitle decoder state for primary and secondary embedded tracks.
final class EmbeddedSubtitlePipeline {
    struct Streams {
        let primary: Int32
        let secondary: Int32
    }

    struct Queues {
        let primary: PacketQueue
        let secondary: PacketQueue
    }

    private struct SlotState {
        var streamIndex: Int32 = -1
        var codecContext: UnsafeMutablePointer<AVCodecContext>?
        var timeBase = AVRational(num: 1, den: 1)
        var packetQueue = PacketQueue(capacity: 64)
        let decodeQueue: DispatchQueue
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.continuum.app",
        category: "EmbeddedSubtitlePipeline"
    )

    private var primary = SlotState(
        decodeQueue: DispatchQueue(label: "com.continuum.coremedia.subtitledecode", qos: .utility)
    )
    private var secondary = SlotState(
        decodeQueue: DispatchQueue(label: "com.continuum.coremedia.subtitledecode.secondary", qos: .utility)
    )

    var streams: Streams {
        Streams(primary: primary.streamIndex, secondary: secondary.streamIndex)
    }

    var queues: Queues {
        Queues(primary: primary.packetQueue, secondary: secondary.packetQueue)
    }

    func streamIndex(for slot: SubtitleSlot) -> Int32 {
        state(for: slot).streamIndex
    }

    func drainQueues() {
        primary.packetQueue.drain()
        secondary.packetQueue.drain()
    }

    func resetQueues() {
        primary.packetQueue = PacketQueue(capacity: 64)
        secondary.packetQueue = PacketQueue(capacity: 64)
    }

    func waitForDecodeQueues() {
        primary.decodeQueue.sync {}
        secondary.decodeQueue.sync {}
    }

    func flushDecoders() {
        if let ctx = primary.codecContext {
            avcodec_flush_buffers(ctx)
        }
        if let ctx = secondary.codecContext {
            avcodec_flush_buffers(ctx)
        }
    }

    func teardown() {
        if primary.codecContext != nil {
            avcodec_free_context(&primary.codecContext)
        }
        if secondary.codecContext != nil {
            avcodec_free_context(&secondary.codecContext)
        }
        primary.streamIndex = -1
        secondary.streamIndex = -1
        drainQueues()
    }

    func setupDecoder(
        formatContext: UnsafeMutablePointer<AVFormatContext>,
        streamIndex: Int32,
        slot: SubtitleSlot,
        session: SubtitleSession?
    ) -> Bool {
        guard streamIndex >= 0,
              streamIndex < Int32(formatContext.pointee.nb_streams),
              let stream = formatContext.pointee.streams?[Int(streamIndex)],
              let codecparPtr = stream.pointee.codecpar
        else { return false }
        let codecpar = codecparPtr.pointee
        guard codecpar.codec_type == AVMEDIA_TYPE_SUBTITLE else { return false }

        guard let codec = avcodec_find_decoder(codecpar.codec_id) else {
            Self.logger.warning("subtitle decoder not found id=\(codecpar.codec_id.rawValue)")
            return false
        }
        var ctx = avcodec_alloc_context3(codec)
        guard ctx != nil else { return false }
        if avcodec_parameters_to_context(ctx, codecparPtr) < 0 {
            avcodec_free_context(&ctx)
            return false
        }
        if avcodec_open2(ctx, codec, nil) < 0 {
            avcodec_free_context(&ctx)
            return false
        }

        let isNativeASS = codecpar.codec_id == AV_CODEC_ID_ASS || codecpar.codec_id == AV_CODEC_ID_SSA
        let headerPtr: UnsafePointer<UInt8>?
        let headerSize: Int
        if let sh = ctx?.pointee.subtitle_header, ctx!.pointee.subtitle_header_size > 0 {
            headerPtr = UnsafePointer(sh)
            headerSize = Int(ctx!.pointee.subtitle_header_size)
        } else {
            headerPtr = codecpar.extradata.map { UnsafePointer($0) }
            headerSize = Int(codecpar.extradata_size)
        }
        session?.openEmbedded(
            slot: slot,
            isNativeASS: isNativeASS,
            extradata: headerPtr,
            extradataSize: headerSize
        )

        updateState(for: slot) { state in
            state.codecContext = ctx
            state.streamIndex = streamIndex
            state.timeBase = stream.pointee.time_base
        }
        Self.logger.info("subtitle decoder opened slot=\(slot.rawValue) stream=\(streamIndex) native=\(isNativeASS)")
        return true
    }

    func startFeed(
        slot: SubtitleSlot,
        session: SubtitleSession?,
        isCancelled: @escaping () -> Bool
    ) {
        guard streamIndex(for: slot) >= 0, codecContext(for: slot) != nil else { return }
        decodeQueue(for: slot).async { [weak self, weak session] in
            guard let self else { return }
            var warnedBitmap = false
            while !isCancelled() {
                let maybePkt = self.packetQueue(for: slot).dequeue()
                guard let pkt = maybePkt else { return }
                defer {
                    var packet: UnsafeMutablePointer<AVPacket>? = pkt
                    av_packet_free(&packet)
                }
                self.decodePacket(pkt, slot: slot, session: session, warnedBitmap: &warnedBitmap)
            }
        }
    }

    func tearDownEmbeddedSlot(slot: SubtitleSlot) {
        let hadEmbeddedStream = streamIndex(for: slot) >= 0 || codecContext(for: slot) != nil
        if hadEmbeddedStream {
            packetQueue(for: slot).enqueue(nil)
            decodeQueue(for: slot).sync {}
        }

        packetQueue(for: slot).drain()
        updateState(for: slot) { state in
            if state.codecContext != nil {
                avcodec_free_context(&state.codecContext)
            }
            state.streamIndex = -1
        }
    }

    private func decodePacket(
        _ pkt: UnsafeMutablePointer<AVPacket>,
        slot: SubtitleSlot,
        session: SubtitleSession?,
        warnedBitmap: inout Bool
    ) {
        guard let ctx = codecContext(for: slot) else { return }
        var sub = AVSubtitle()
        defer { avsubtitle_free(&sub) }
        var gotSubtitle: Int32 = 0
        let result = avcodec_decode_subtitle2(ctx, &sub, &gotSubtitle, pkt)
        guard result >= 0, gotSubtitle != 0 else { return }

        let noPts = Int64.min
        let ptsRaw: Int64 = pkt.pointee.pts != noPts ? pkt.pointee.pts
            : (pkt.pointee.dts != noPts ? pkt.pointee.dts : 0)
        let tb = timeBase(for: slot)
        let basePtsSeconds = Double(ptsRaw) * Double(tb.num) / Double(tb.den)
        let startMs = Int64((basePtsSeconds + Double(sub.start_display_time) / 1000.0) * 1000.0)
        let endMs: Int64 = {
            if sub.end_display_time != UInt32.max,
               sub.end_display_time > sub.start_display_time {
                return Int64((basePtsSeconds + Double(sub.end_display_time) / 1000.0) * 1000.0)
            }
            if pkt.pointee.duration > 0 {
                let durSeconds = Double(pkt.pointee.duration) * Double(tb.num) / Double(tb.den)
                return startMs + Int64(durSeconds * 1000.0)
            }
            return startMs + 5000
        }()
        let durationMs = max(Int64(0), endMs - startMs)

        for index in 0..<Int(sub.num_rects) {
            guard let rect = sub.rects[index]?.pointee else { continue }
            if rect.type == SUBTITLE_BITMAP {
                if !warnedBitmap {
                    warnedBitmap = true
                    Self.logger.info("bitmap subtitle packet ignored (server filters PGS/DVB/VOBSUB)")
                }
                continue
            }
            if let assPtr = rect.ass {
                let ass = String(cString: assPtr)
                if !ass.isEmpty {
                    session?.feedEmbedded(
                        slot: slot,
                        eventText: ass,
                        startMs: startMs,
                        durationMs: durationMs
                    )
                }
            }
        }
    }

    private func codecContext(for slot: SubtitleSlot) -> UnsafeMutablePointer<AVCodecContext>? {
        state(for: slot).codecContext
    }

    private func timeBase(for slot: SubtitleSlot) -> AVRational {
        state(for: slot).timeBase
    }

    private func packetQueue(for slot: SubtitleSlot) -> PacketQueue {
        state(for: slot).packetQueue
    }

    private func decodeQueue(for slot: SubtitleSlot) -> DispatchQueue {
        state(for: slot).decodeQueue
    }

    private func state(for slot: SubtitleSlot) -> SlotState {
        switch slot {
        case .primary: primary
        case .secondary: secondary
        }
    }

    private func updateState(for slot: SubtitleSlot, _ update: (inout SlotState) -> Void) {
        switch slot {
        case .primary: update(&primary)
        case .secondary: update(&secondary)
        }
    }
}
