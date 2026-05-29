import Foundation
import MnemeCore

@MainActor
final class AppEnvironment: ObservableObject {
    let embedder: any EmbeddingService
    let store: IndexStore
    let query: QueryService
    let sources = SourcesStore()
    let sourceWatcher = SourceFolderWatcher()
    let transcriptStore: TranscriptStore
    let transcriptionService: any TranscriptionService
    let activitySummaryGenerator: any ActivitySummaryGenerator

    @Published var isIndexing = false
    @Published var lastStats: IndexRunStats?
    @Published var statusMessage = ""

    private init(
        embedder: any EmbeddingService,
        store: IndexStore,
        transcriptStore: TranscriptStore,
        transcriptionService: any TranscriptionService,
        activitySummaryGenerator: any ActivitySummaryGenerator,
        ragAnswerGenerator: any RagAnswerGenerator
    ) {
        self.embedder = embedder
        self.store = store
        self.transcriptStore = transcriptStore
        self.transcriptionService = transcriptionService
        self.activitySummaryGenerator = activitySummaryGenerator
        self.query = QueryService(embedder: embedder, store: store, ragAnswerGenerator: ragAnswerGenerator)
    }

    static func make() -> AppEnvironment {
        let directory = appSupportDir()
        let coreML = CoreMLE5Loader.loadEmbedder(appSupportDirectory: directory)
        let embedder: any EmbeddingService = coreML.embedder
            ?? (try? NLEmbeddingService())
            ?? HashingEmbeddingService(dimension: 256)
        let databasePath = directory.appendingPathComponent("index.sqlite").path
        let transcriptStore = TranscriptStore(
            directory: directory.appendingPathComponent("Transcripts", isDirectory: true)
        )
        let transcriptionService = WhisperKitTranscriptionService(
            modelDirectory: directory.appendingPathComponent("Models/WhisperKit", isDirectory: true)
        )
        let store = openStore(path: databasePath, embedder: embedder)
        let mlxTextGenerator = MLXLocalTextGenerator(
            modelDirectory: directory.appendingPathComponent("Models/MLX", isDirectory: true)
        )
        let ragAnswerGenerator = ResilientRagAnswerGenerator(
            primary: MLXLocalRagAnswerGenerator(textGenerator: mlxTextGenerator)
        )
        let activitySummaryGenerator = ResilientActivitySummaryGenerator(
            primary: MLXLocalActivitySummaryGenerator(textGenerator: mlxTextGenerator)
        )
        let environment = AppEnvironment(
            embedder: embedder,
            store: store,
            transcriptStore: transcriptStore,
            transcriptionService: transcriptionService,
            activitySummaryGenerator: activitySummaryGenerator,
            ragAnswerGenerator: ragAnswerGenerator
        )
        if let resourcesURL = coreML.resourcesURL {
            environment.statusMessage = "CoreML e5 已加载: \(resourcesURL.path)"
        } else if embedder.id.hasPrefix("nl-sentence") {
            environment.statusMessage = "CoreML e5 资源未安装，使用 NLEmbedding"
        }
        QuickSearchController.shared.configure(query: environment.query)
        let hotKey = HotKeyPreferences().loadQuickSearchHotKey()
        if !GlobalHotKeyController.shared.registerQuickSearchHotKey(hotKey) {
            environment.statusMessage = "快搜热键 \(hotKey.displayName) 注册失败"
        }
        return environment
    }

    static func appSupportDir() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = base.appendingPathComponent("Mneme", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func openStore(path: String, embedder: any EmbeddingService) -> IndexStore {
        do {
            return try IndexStore(path: path, embedderId: embedder.id, dimension: embedder.dimension)
        } catch {
            quarantineIncompatibleIndex(atPath: path)
            do {
                return try IndexStore(path: path, embedderId: embedder.id, dimension: embedder.dimension)
            } catch {
                return try! IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
            }
        }
    }

    private static func quarantineIncompatibleIndex(atPath path: String) {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let source = path + suffix
            guard fileManager.fileExists(atPath: source) else {
                continue
            }
            let destination = "\(source).incompatible-\(timestamp)"
            try? fileManager.moveItem(atPath: source, toPath: destination)
        }
    }

    func reindex() async {
        guard !isIndexing else { return }
        isIndexing = true
        statusMessage = "索引中..."
        defer { isIndexing = false }

        do {
            let pipeline = IndexingPipeline(
                connectors: sources.connectors(),
                embedder: embedder,
                store: store
            )
            let stats = try await pipeline.run { [weak self] message in
                Task { @MainActor in
                    self?.statusMessage = message
                }
            }
            lastStats = stats
            statusMessage = "完成: 新增 \(stats.indexed), 跳过 \(stats.skipped), 失败 \(stats.failed)"
        } catch {
            statusMessage = "索引出错: \(error.localizedDescription)"
        }
    }

    func startSourceWatching() {
        sourceWatcher.start(sourceURLs: sources.sourceURLs()) { [weak self] in
            await self?.reindex()
        }
        statusMessage = sourceWatcher.isWatching ? "来源监听已启动" : "来源监听启动失败"
    }

    func stopSourceWatching() {
        sourceWatcher.stop()
        statusMessage = "来源监听已停止"
    }

    func transcriptStoreDirectory() -> URL {
        Self.appSupportDir().appendingPathComponent("Transcripts", isDirectory: true)
    }

    func whisperModelDirectory() -> URL {
        Self.appSupportDir().appendingPathComponent("Models/WhisperKit", isDirectory: true)
    }
}
