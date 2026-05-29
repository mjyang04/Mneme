import Foundation

public struct TranscriptImportService: Sendable {
    private let store: TranscriptStore
    private let now: @Sendable () -> Date

    public init(store: TranscriptStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    public func importPlainText(
        title: String,
        text: String,
        language: String? = nil
    ) throws -> TranscriptDocument {
        let createdAt = now()
        let id = "\(Self.slug(title))-\(Int(createdAt.timeIntervalSince1970))"
        let document = TranscriptDocument(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Transcript" : title,
            sourceAudioPath: nil,
            duration: 0,
            language: language,
            model: "manual",
            createdAt: createdAt,
            segments: [
                TranscriptSegment(start: 0, end: 0, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            ]
        )
        try store.save(document)
        return document
    }

    public func importAudio(
        audio: URL,
        title: String? = nil,
        options: TranscribeOptions = TranscribeOptions(),
        service: any TranscriptionService
    ) async throws -> TranscriptDocument {
        try AudioFileSupport.validate(audio)

        var segments: [TranscriptSegment] = []
        for try await segment in service.transcribe(audio, options: options) {
            let text = TranscriptTextCleaner.clean(segment.text)
            guard !text.isEmpty else { continue }
            segments.append(TranscriptSegment(start: segment.start, end: segment.end, text: text))
        }

        guard !segments.isEmpty else {
            throw TranscriptImportError.emptyTranscript
        }

        let createdAt = now()
        let resolvedTitle = Self.transcriptTitle(title: title, audio: audio)
        let id = "\(Self.slug(resolvedTitle))-\(Int(createdAt.timeIntervalSince1970))"
        let document = TranscriptDocument(
            id: id,
            title: resolvedTitle,
            sourceAudioPath: audio.path,
            duration: segments.map(\.end).max() ?? 0,
            language: options.language,
            model: options.model,
            createdAt: createdAt,
            segments: segments
        )
        try store.save(document)
        return document
    }

    private static func slug(_ text: String) -> String {
        let cleaned = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }

    private static func transcriptTitle(title: String?, audio: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return audio.deletingPathExtension().lastPathComponent
    }
}
