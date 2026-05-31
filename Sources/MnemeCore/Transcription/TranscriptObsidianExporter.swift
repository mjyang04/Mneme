import Foundation

public struct TranscriptObsidianExporter: Sendable {
    public static let startMarker = "<!-- mneme:transcript:start -->"
    public static let endMarker = "<!-- mneme:transcript:end -->"

    private let outputDirectory: URL

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    @discardableResult
    public func export(_ document: TranscriptDocument) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appendingPathComponent(filename(for: document))
        let block = renderManagedBlock(document)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = replaceManagedBlock(in: existing, with: block)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func renderManagedBlock(_ document: TranscriptDocument) -> String {
        var lines: [String] = [
            Self.startMarker,
            "---",
            "type: transcript",
            "transcript_id: \"\(document.id)\"",
            "source_audio: \"\(document.sourceAudioPath ?? "")\"",
            "duration: \(formatDuration(document.duration))",
            "language: \(document.language ?? "")",
            "model: \(document.model)",
            "created: \(dateSlug(document.createdAt))",
            "---",
            ""
        ]
        lines.append(contentsOf: document.segments.map {
            "- [\(formatTimestamp($0.start))] \($0.text)"
        })
        lines.append(Self.endMarker)
        return lines.joined(separator: "\n")
    }

    private func filename(for document: TranscriptDocument) -> String {
        "\(dateSlug(document.createdAt))-\(slug(document.title))-\(slug(document.id)).md"
    }

    private func replaceManagedBlock(in text: String, with block: String) -> String {
        guard let start = text.range(of: Self.startMarker),
              let end = text.range(of: Self.endMarker, range: start.upperBound..<text.endIndex) else {
            if text.isEmpty {
                return block + "\n"
            }
            let separator = text.hasSuffix("\n") ? "\n" : "\n\n"
            return text + separator + block + "\n"
        }
        var updated = text
        updated.replaceSubrange(start.lowerBound..<end.upperBound, with: block)
        return updated
    }

    private func formatTimestamp(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        formatTimestamp(value)
    }

    private func dateSlug(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func slug(_ text: String) -> String {
        let cleaned = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "transcript" : collapsed
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
