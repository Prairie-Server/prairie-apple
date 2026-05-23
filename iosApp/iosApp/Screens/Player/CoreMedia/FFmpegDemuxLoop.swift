import Foundation
import Libavcodec
import Libavformat
import QuartzCore

struct FFmpegDemuxLoop {
    struct Streams {
        let video: () -> Int32
        let audio: () -> Int32
        let subtitlePrimary: () -> Int32
        let subtitleSecondary: () -> Int32
    }

    struct Queues {
        let video: PacketQueue
        let audio: PacketQueue
        let subtitlePrimary: PacketQueue
        let subtitleSecondary: PacketQueue

        func enqueueSentinels() {
            video.enqueue(nil)
            audio.enqueue(nil)
            subtitlePrimary.enqueue(nil)
            subtitleSecondary.enqueue(nil)
        }
    }

    static func run(
        formatContext: UnsafeMutablePointer<AVFormatContext>,
        streams: Streams,
        queues: Queues,
        isCancelled: () -> Bool,
        shouldThrottle: () -> Bool,
        ioTimeoutSeconds: () -> CFTimeInterval,
        lastProgressWall: () -> CFTimeInterval,
        onReadEntered: () -> Void,
        onReadReturned: () -> Void,
        onProgress: () -> Void,
        onReadError: (Int32) -> Void,
        onEOF: () -> Void
    ) {
        var reportedReadError = false
        let eofCode = Int32(bitPattern: 0x20464F45) // 'EOF '
        let avErrorEOF = -eofCode
        let exitCode = Int32(bitPattern: 0x54495845) // 'EXIT'
        let avErrorExit = -exitCode

        while !isCancelled() {
            if shouldThrottle() {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            guard let packet = av_packet_alloc() else { break }
            onReadEntered()
            let readResult = av_read_frame(formatContext, packet)
            onReadReturned()
            if readResult >= 0 {
                onProgress()
            }
            if readResult < 0 {
                var packetToFree: UnsafeMutablePointer<AVPacket>? = packet
                av_packet_free(&packetToFree)

                let interruptedDuringRecentProgress = readResult == avErrorExit
                    && CACurrentMediaTime() - lastProgressWall() < ioTimeoutSeconds()
                if readResult == avErrorEOF {
                    onEOF()
                } else if !isCancelled(), !interruptedDuringRecentProgress, !reportedReadError {
                    reportedReadError = true
                    onReadError(readResult)
                }
                queues.enqueueSentinels()
                return
            }

            route(packet: packet, streams: streams, queues: queues)
            if isCancelled() { break }
        }
        queues.enqueueSentinels()
    }

    private static func route(
        packet: UnsafeMutablePointer<AVPacket>,
        streams: Streams,
        queues: Queues
    ) {
        let streamIndex = packet.pointee.stream_index
        if streamIndex == streams.video() {
            queues.video.enqueue(packet)
        } else if streamIndex == streams.audio() {
            queues.audio.enqueue(packet)
        } else if streamIndex == streams.subtitlePrimary() {
            queues.subtitlePrimary.enqueue(packet)
        } else if streamIndex == streams.subtitleSecondary() {
            queues.subtitleSecondary.enqueue(packet)
        } else {
            var packetToFree: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&packetToFree)
        }
    }
}
