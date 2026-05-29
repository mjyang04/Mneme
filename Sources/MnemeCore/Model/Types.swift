import Foundation

public enum SourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case notes
    case pdf
    case code
    case transcript
    case activity

    public var id: String { rawValue }
}

public struct SourceItem: Sendable, Equatable {
    public let id: String
    public let uri: URL
    public let modifiedAt: Date?

    public init(id: String, uri: URL, modifiedAt: Date?) {
        self.id = id
        self.uri = uri
        self.modifiedAt = modifiedAt
    }
}

public struct ExtractedDocument: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let text: String
    public let contentHash: String
    public let meta: [String: String]

    public init(
        id: String,
        title: String?,
        text: String,
        contentHash: String,
        meta: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.contentHash = contentHash
        self.meta = meta
    }
}

public struct TextLocator: Codable, Equatable, Sendable {
    public var page: Int?
    public var startChar: Int?
    public var endChar: Int?
    public var startLine: Int?
    public var endLine: Int?

    public init(
        page: Int? = nil,
        startChar: Int? = nil,
        endChar: Int? = nil,
        startLine: Int? = nil,
        endLine: Int? = nil
    ) {
        self.page = page
        self.startChar = startChar
        self.endChar = endChar
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct Chunk: Sendable, Equatable {
    public let ordinal: Int
    public let text: String
    public let locator: TextLocator

    public init(ordinal: Int, text: String, locator: TextLocator) {
        self.ordinal = ordinal
        self.text = text
        self.locator = locator
    }
}

public struct SearchFilter: Sendable, Equatable {
    public var kinds: [SourceKind]?
    public var sourceIds: [String]?

    public init(kinds: [SourceKind]? = nil, sourceIds: [String]? = nil) {
        self.kinds = kinds
        self.sourceIds = sourceIds
    }
}

public struct SearchHit: Sendable, Equatable {
    public let chunkId: String
    public let documentId: String
    public let score: Float
    public let text: String
    public let title: String?
    public let uri: URL
    public let kind: SourceKind
    public let locator: TextLocator?

    public init(
        chunkId: String,
        documentId: String,
        score: Float,
        text: String,
        title: String?,
        uri: URL,
        kind: SourceKind,
        locator: TextLocator?
    ) {
        self.chunkId = chunkId
        self.documentId = documentId
        self.score = score
        self.text = text
        self.title = title
        self.uri = uri
        self.kind = kind
        self.locator = locator
    }
}
