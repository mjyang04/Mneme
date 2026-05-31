import Foundation

public struct QueryServiceRuntime: Sendable {
    public let appSupportDirectory: URL
    public let databaseURL: URL
    public let embedder: any EmbeddingService
    public let store: IndexStore
    public let query: QueryService
    public let e5ResourcesURL: URL?

    public init(
        appSupportDirectory: URL,
        databaseURL: URL,
        embedder: any EmbeddingService,
        store: IndexStore,
        query: QueryService,
        e5ResourcesURL: URL?
    ) {
        self.appSupportDirectory = appSupportDirectory
        self.databaseURL = databaseURL
        self.embedder = embedder
        self.store = store
        self.query = query
        self.e5ResourcesURL = e5ResourcesURL
    }
}

public enum QueryServiceFactory {
    public static func defaultAppSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = base.appendingPathComponent("Mneme", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func makeReadWrite(
        appSupportDirectory: URL? = nil,
        ragAnswerGenerator: any RagAnswerGenerator = ExtractiveRagAnswerGenerator()
    ) throws -> QueryServiceRuntime {
        let directory: URL
        if let appSupportDirectory {
            directory = appSupportDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            directory = try defaultAppSupportDirectory()
        }
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let embedding = makeBestAvailableEmbedder(appSupportDirectory: directory)
        let store = try IndexStore(
            path: databaseURL.path,
            embedderId: embedding.embedder.id,
            dimension: embedding.embedder.dimension
        )
        let query = QueryService(
            embedder: embedding.embedder,
            store: store,
            ragAnswerGenerator: ragAnswerGenerator
        )
        return QueryServiceRuntime(
            appSupportDirectory: directory,
            databaseURL: databaseURL,
            embedder: embedding.embedder,
            store: store,
            query: query,
            e5ResourcesURL: embedding.e5ResourcesURL
        )
    }

    public static func makeReadOnly(
        appSupportDirectory: URL? = nil,
        ragAnswerGenerator: any RagAnswerGenerator = ExtractiveRagAnswerGenerator()
    ) throws -> QueryServiceRuntime {
        let directory: URL
        if let appSupportDirectory {
            directory = appSupportDirectory
        } else {
            directory = try defaultAppSupportDirectory()
        }
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw MnemeAgentError.missingIndex(databaseURL.path)
        }

        let config = try IndexStore.readConfig(path: databaseURL.path)
        let embedding = try makeEmbedder(
            appSupportDirectory: directory,
            requiredConfig: config
        )
        let store = try IndexStore(
            readonlyPath: databaseURL.path,
            embedderId: embedding.embedder.id,
            dimension: embedding.embedder.dimension
        )
        let query = QueryService(
            embedder: embedding.embedder,
            store: store,
            ragAnswerGenerator: ragAnswerGenerator
        )
        return QueryServiceRuntime(
            appSupportDirectory: directory,
            databaseURL: databaseURL,
            embedder: embedding.embedder,
            store: store,
            query: query,
            e5ResourcesURL: embedding.e5ResourcesURL
        )
    }

    public static func makeBestAvailableEmbedder(
        appSupportDirectory: URL
    ) -> (embedder: any EmbeddingService, e5ResourcesURL: URL?) {
        let coreML = CoreMLE5Loader.loadEmbedder(appSupportDirectory: appSupportDirectory)
        if let embedder = coreML.embedder {
            return (embedder, coreML.resourcesURL)
        }
        if let embedder = try? NLEmbeddingService() {
            return (embedder, nil)
        }
        return (HashingEmbeddingService(dimension: 256), nil)
    }

    private static func makeEmbedder(
        appSupportDirectory: URL,
        requiredConfig: IndexStoreConfig?
    ) throws -> (embedder: any EmbeddingService, e5ResourcesURL: URL?) {
        guard let requiredConfig else {
            return makeBestAvailableEmbedder(appSupportDirectory: appSupportDirectory)
        }

        if requiredConfig.embedderId == "coreml-e5-small-v1" {
            let coreML = CoreMLE5Loader.loadEmbedder(appSupportDirectory: appSupportDirectory)
            guard let embedder = coreML.embedder,
                  embedder.dimension == requiredConfig.dimension else {
                throw EmbeddingError.modelUnavailable
            }
            return (embedder, coreML.resourcesURL)
        }

        if requiredConfig.embedderId.hasPrefix("nl-sentence-"),
           let embedder = try? NLEmbeddingService(),
           embedder.id == requiredConfig.embedderId,
           embedder.dimension == requiredConfig.dimension {
            return (embedder, nil)
        }

        if requiredConfig.embedderId.hasPrefix("hashing-v1-d") {
            let embedder = HashingEmbeddingService(dimension: requiredConfig.dimension)
            guard embedder.id == requiredConfig.embedderId else {
                throw EmbeddingError.dimensionMismatch
            }
            return (embedder, nil)
        }

        throw EmbeddingError.dimensionMismatch
    }
}
