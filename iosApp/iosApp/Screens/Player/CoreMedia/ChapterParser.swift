import Foundation
import Libavformat
import Libavutil

/// Reads chapter markers out of an `AVFormatContext` and shapes them into
/// `PlayerCore.ChapterInfo`. Pure function over the format context — no
/// PlayerCore state is captured, so the same routine can be reused by
/// alternate demux pipelines if/when they exist.
enum ChapterParser {
    static func parse(formatContext: UnsafeMutablePointer<AVFormatContext>?) -> [PlayerCore.ChapterInfo] {
        guard let formatContext else { return [] }
        let n = Int(formatContext.pointee.nb_chapters)
        guard n > 0, let arr = formatContext.pointee.chapters else { return [] }

        var result: [PlayerCore.ChapterInfo] = []
        result.reserveCapacity(n)
        for i in 0..<n {
            guard let chPtr = arr[i] else { continue }
            let ch = chPtr.pointee
            let tb = ch.time_base
            let seconds = Double(ch.start) * Double(tb.num) / Double(tb.den)
            var title: String?
            if let meta = ch.metadata {
                let entry = av_dict_get(meta, "title", nil, 0)
                if let entry, let cstr = entry.pointee.value {
                    title = String(cString: cstr)
                }
            }
            result.append(PlayerCore.ChapterInfo(index: i, title: title, time: seconds))
        }
        return result
    }
}
