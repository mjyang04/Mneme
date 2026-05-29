import Foundation

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct TranscriptDocument: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let sourceAudioPath: String?
    public let duration: TimeInterval
    public let language: String?
    public let model: String
    public let createdAt: Date
    public let segments: [TranscriptSegment]

    public init(
        id: String,
        title: String,
        sourceAudioPath: String?,
        duration: TimeInterval,
        language: String?,
        model: String,
        createdAt: Date,
        segments: [TranscriptSegment]
    ) {
        self.id = id
        self.title = title
        self.sourceAudioPath = sourceAudioPath
        self.duration = duration
        self.language = language
        self.model = model
        self.createdAt = createdAt
        self.segments = segments
    }

    public var fullText: String {
        segments.map(\.text).joined(separator: "\n")
    }
}

public protocol TranscriptionService: Sendable {
    func transcribe(_ audio: URL, options: TranscribeOptions) -> AsyncThrowingStream<TranscriptSegment, Error>
}

public struct TranscribeOptions: Codable, Equatable, Sendable {
    public let model: String
    public let language: String?
    public let allowsModelDownload: Bool

    public init(
        model: String = "large-v3-v20240930_626MB",
        language: String? = nil,
        allowsModelDownload: Bool = false
    ) {
        self.model = model
        self.language = language
        self.allowsModelDownload = allowsModelDownload
    }
}

public enum TranscriptImportError: LocalizedError, Equatable {
    case emptyTranscript
    case unsupportedAudioExtension(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "转写结果为空。"
        case let .unsupportedAudioExtension(ext):
            "不支持的音频格式: \(ext)"
        }
    }
}

public enum AudioFileSupport {
    public static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "flac", "mov", "mp4", "aac", "aif", "aiff"]

    public static func validate(_ url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw TranscriptImportError.unsupportedAudioExtension(ext.isEmpty ? "(none)" : ext)
        }
    }
}

public enum TranscriptTextCleaner {
    public static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
