import Foundation

public struct SearchHitDTO: Codable, Equatable, Sendable {
    public let score: Float
    public let title: String?
    public let uri: String
    public let kind: String
    public let text: String
    public let documentId: String
    public let locator: TextLocator?
    public let sourceURL: String?

    public init(
        score: Float,
        title: String?,
        uri: String,
        kind: String,
        text: String,
        documentId: String,
        locator: TextLocator?,
        sourceURL: String? = nil
    ) {
        self.score = score
        self.title = title
        self.uri = uri
        self.kind = kind
        self.text = text
        self.documentId = documentId
        self.locator = locator
        self.sourceURL = sourceURL
    }

    public init(hit: SearchHit) {
        self.init(
            score: hit.score,
            title: hit.title,
            uri: hit.uri.absoluteString,
            kind: hit.kind.rawValue,
            text: hit.text,
            documentId: hit.documentId,
            locator: hit.locator,
            sourceURL: hit.meta["source_url"]
        )
    }
}

public struct SearchResultDTO: Codable, Equatable, Sendable {
    public let hits: [SearchHitDTO]

    public init(hits: [SearchHitDTO]) {
        self.hits = hits
    }
}

public struct AnswerDTO: Codable, Equatable, Sendable {
    public let answer: String
    public let citations: [SearchHitDTO]

    public init(answer: String, citations: [SearchHitDTO]) {
        self.answer = answer
        self.citations = citations
    }
}

public struct SourceSummaryDTO: Codable, Equatable, Sendable {
    public let sourceId: String
    public let kind: String
    public let path: String
    public let documentCount: Int

    public init(sourceId: String, kind: String, path: String, documentCount: Int) {
        self.sourceId = sourceId
        self.kind = kind
        self.path = path
        self.documentCount = documentCount
    }
}

public struct SourcesResultDTO: Codable, Equatable, Sendable {
    public let sources: [SourceSummaryDTO]

    public init(sources: [SourceSummaryDTO]) {
        self.sources = sources
    }
}

public struct DoctorDTO: Codable, Equatable, Sendable {
    public let appSupportDir: String
    public let indexPath: String
    public let indexReadable: Bool
    public let documentCount: Int
    public let embedderId: String
    public let dimension: Int
    public let e5ResourcesPath: String?
    public let capabilities: [String]

    public init(
        appSupportDir: String,
        indexPath: String,
        indexReadable: Bool,
        documentCount: Int,
        embedderId: String,
        dimension: Int,
        e5ResourcesPath: String?,
        capabilities: [String]
    ) {
        self.appSupportDir = appSupportDir
        self.indexPath = indexPath
        self.indexReadable = indexReadable
        self.documentCount = documentCount
        self.embedderId = embedderId
        self.dimension = dimension
        self.e5ResourcesPath = e5ResourcesPath
        self.capabilities = capabilities
    }
}

public struct RememberInputDTO: Codable, Equatable, Sendable {
    public let text: String
    public let tags: [String]?
    public let sourceRef: String?
    public let link: String?
    public let title: String?

    public init(
        text: String,
        tags: [String]? = nil,
        sourceRef: String? = nil,
        link: String? = nil,
        title: String? = nil
    ) {
        self.text = text
        self.tags = tags
        self.sourceRef = sourceRef
        self.link = link
        self.title = title
    }
}

public struct RememberResultDTO: Codable, Equatable, Sendable {
    public let key: String
    public let path: String
    public let deduped: Bool
    public let indexed: Bool

    public init(key: String, path: String, deduped: Bool, indexed: Bool) {
        self.key = key
        self.path = path
        self.deduped = deduped
        self.indexed = indexed
    }
}
