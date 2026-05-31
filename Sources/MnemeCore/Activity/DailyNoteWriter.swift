import Foundation

public struct DailyNoteWriter: Sendable {
    private let dailyDirectory: URL

    public init(dailyDirectory: URL) {
        self.dailyDirectory = dailyDirectory
    }

    @discardableResult
    public func writeManagedBlock(_ block: String, day: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: dailyDirectory,
            withIntermediateDirectories: true
        )
        let url = dailyDirectory.appendingPathComponent("\(day).md")
        let managedBlock = normalizeManagedBlock(block)

        let existing: String
        if FileManager.default.fileExists(atPath: url.path) {
            existing = try String(contentsOf: url, encoding: .utf8)
        } else {
            existing = "# \(day)\n"
        }
        let updated = replaceManagedBlock(in: existing, with: managedBlock)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func normalizeManagedBlock(_ block: String) -> String {
        if block.contains(DailyActivityRenderer.startMarker),
           block.contains(DailyActivityRenderer.endMarker) {
            return block
        }
        return [
            DailyActivityRenderer.startMarker,
            block,
            DailyActivityRenderer.endMarker
        ].joined(separator: "\n")
    }

    private func replaceManagedBlock(in text: String, with block: String) -> String {
        let starts = text.ranges(of: DailyActivityRenderer.startMarker)
        let ends = text.ranges(of: DailyActivityRenderer.endMarker)
        guard starts.count == 1,
              ends.count == 1,
              let start = starts.first,
              let end = ends.first,
              start.upperBound <= end.lowerBound else {
            let separator = text.hasSuffix("\n") ? "\n" : "\n\n"
            return text + separator + block + "\n"
        }

        let replaceRange = start.lowerBound..<end.upperBound
        var updated = text
        updated.replaceSubrange(replaceRange, with: block)
        return updated
    }
}

private extension String {
    func ranges(of needle: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = startIndex..<endIndex
        while let range = self.range(of: needle, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<endIndex
        }
        return ranges
    }
}
