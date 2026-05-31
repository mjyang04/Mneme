import Darwin
import Foundation
import MnemeCore

enum MnemeCLI {
    static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }
        arguments.removeFirst()

        switch command {
        case "search":
            try await runSearch(arguments)
        case "answer":
            try await runAnswer(arguments)
        case "sources":
            try await runSources(arguments)
        case "remember":
            try await runRemember(arguments)
        case "doctor":
            try await runDoctor(arguments)
        case "mcp":
            try await MCPServer(appSupportDirectory: appSupportDirectory(from: &arguments)).run()
        case "-h", "--help", "help":
            printUsage()
        default:
            throw MnemeAgentError.invalidArgument("Unknown command: \(command)")
        }
    }

    private static func runSearch(_ input: [String]) async throws {
        var arguments = input
        let json = takeFlag("--json", from: &arguments)
        let topK = try takeInt("--top-k", defaultValue: 20, from: &arguments)
        let kinds = try parseKinds(takeValue("--kinds", from: &arguments))
        let sourceIds = parseCSV(takeValue("--source-ids", from: &arguments))
        let appSupport = appSupportDirectory(from: &arguments)
        let query = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw MnemeAgentError.invalidArgument("search requires a query")
        }

        let facade = try makeFacade(appSupportDirectory: appSupport)
        let result = try await facade.search(
            query: query,
            topK: topK,
            kinds: kinds,
            sourceIds: sourceIds
        )
        if json {
            try printJSON(result)
        } else {
            for (index, hit) in result.hits.enumerated() {
                print("[\(index + 1)] \(hit.title ?? hit.documentId) \(String(format: "%.4f", hit.score))")
                print(hit.uri)
                print(hit.text)
                print("")
            }
        }
    }

    private static func runAnswer(_ input: [String]) async throws {
        var arguments = input
        let json = takeFlag("--json", from: &arguments)
        let topK = try takeInt("--top-k", defaultValue: 8, from: &arguments)
        let kinds = try parseKinds(takeValue("--kinds", from: &arguments))
        let sourceIds = parseCSV(takeValue("--source-ids", from: &arguments))
        let appSupport = appSupportDirectory(from: &arguments)
        if takeFlag("--mlx", from: &arguments) {
            throw MnemeAgentError.invalidArgument("mneme CLI does not support --mlx; use the macOS app for MLX generation")
        }
        let question = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw MnemeAgentError.invalidArgument("answer requires a question")
        }

        let facade = try makeFacade(appSupportDirectory: appSupport)
        let result = try await facade.answer(
            question: question,
            topK: topK,
            kinds: kinds,
            sourceIds: sourceIds
        )
        if json {
            try printJSON(result)
        } else {
            print(result.answer)
            if !result.citations.isEmpty {
                print("")
                for (index, hit) in result.citations.enumerated() {
                    print("[\(index + 1)] \(hit.title ?? hit.documentId) \(hit.uri)")
                }
            }
        }
    }

    private static func runSources(_ input: [String]) async throws {
        var arguments = input
        let json = takeFlag("--json", from: &arguments)
        let appSupport = appSupportDirectory(from: &arguments)
        guard arguments.isEmpty else {
            throw MnemeAgentError.invalidArgument("sources does not accept positional arguments")
        }

        let facade = try makeFacade(appSupportDirectory: appSupport)
        let result = try await facade.sources()
        if json {
            try printJSON(result)
        } else {
            for source in result.sources {
                print("\(source.sourceId)\t\(source.kind)\t\(source.documentCount)\t\(source.path)")
            }
        }
    }

    private static func runRemember(_ input: [String]) async throws {
        var arguments = input
        let json = takeFlag("--json", from: &arguments)
        let tags = parseCSV(takeValue("--tags", from: &arguments))
        let sourceRef = takeValue("--source-ref", from: &arguments)
        let link = takeValue("--link", from: &arguments)
        let title = takeValue("--title", from: &arguments)
        let appSupport = appSupportDirectory(from: &arguments)
        let text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw MnemeAgentError.invalidArgument("remember requires text")
        }

        let runtime = try QueryServiceFactory.makeReadWrite(appSupportDirectory: appSupport)
        let facade = MnemeQueryFacade(runtime: runtime)
        let result = try await facade.remember(RememberInputDTO(
            text: text,
            tags: tags,
            sourceRef: sourceRef,
            link: link,
            title: title
        ))
        if json {
            try printJSON(result)
        } else {
            print(result.path)
            print("key: \(result.key)")
            print("deduped: \(result.deduped)")
            print("indexed: \(result.indexed)")
        }
    }

    private static func runDoctor(_ input: [String]) async throws {
        var arguments = input
        let json = takeFlag("--json", from: &arguments)
        let appSupport = appSupportDirectory(from: &arguments)
        guard arguments.isEmpty else {
            throw MnemeAgentError.invalidArgument("doctor does not accept positional arguments")
        }

        let result = await makeDoctor(appSupportDirectory: appSupport)
        if json {
            try printJSON(result)
        } else {
            print("appSupportDir: \(result.appSupportDir)")
            print("indexPath: \(result.indexPath)")
            print("indexReadable: \(result.indexReadable)")
            print("documentCount: \(result.documentCount)")
            print("embedder: \(result.embedderId) / \(result.dimension)")
            if let e5ResourcesPath = result.e5ResourcesPath {
                print("e5ResourcesPath: \(e5ResourcesPath)")
            }
            print("capabilities: \(result.capabilities.joined(separator: ", "))")
        }
    }

    private static func makeFacade(appSupportDirectory: URL?) throws -> MnemeQueryFacade {
        let runtime = try QueryServiceFactory.makeReadOnly(appSupportDirectory: appSupportDirectory)
        return MnemeQueryFacade(runtime: runtime)
    }

    private static func makeDoctor(appSupportDirectory: URL?) async -> DoctorDTO {
        let directory: URL
        if let appSupportDirectory {
            directory = appSupportDirectory
        } else if let defaultDirectory = try? QueryServiceFactory.defaultAppSupportDirectory() {
            directory = defaultDirectory
        } else {
            directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Mneme")
        }
        if let runtime = try? QueryServiceFactory.makeReadOnly(appSupportDirectory: directory) {
            return await MnemeQueryFacade(runtime: runtime).doctor()
        }

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let embedding = QueryServiceFactory.makeBestAvailableEmbedder(appSupportDirectory: directory)
        return DoctorDTO(
            appSupportDir: directory.path,
            indexPath: databaseURL.path,
            indexReadable: FileManager.default.isReadableFile(atPath: databaseURL.path),
            documentCount: 0,
            embedderId: embedding.embedder.id,
            dimension: embedding.embedder.dimension,
            e5ResourcesPath: embedding.e5ResourcesURL?.path,
            capabilities: [
                "local-first",
                "search",
                "extractive-answer",
                "sources",
                "remember",
                "stdio-mcp"
            ]
        )
    }

    private static func appSupportDirectory(from arguments: inout [String]) -> URL? {
        if let value = takeValue("--app-support", from: &arguments) {
            return URL(fileURLWithPath: value)
        }
        if let value = ProcessInfo.processInfo.environment["MNEME_APP_SUPPORT_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value)
        }
        return nil
    }

    private static func takeFlag(_ name: String, from arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: name) else {
            return false
        }
        arguments.remove(at: index)
        return true
    }

    private static func takeValue(_ name: String, from arguments: inout [String]) -> String? {
        guard let index = arguments.firstIndex(of: name) else {
            return nil
        }
        arguments.remove(at: index)
        guard index < arguments.count else {
            return nil
        }
        return arguments.remove(at: index)
    }

    private static func takeInt(_ name: String, defaultValue: Int, from arguments: inout [String]) throws -> Int {
        guard let raw = takeValue(name, from: &arguments) else {
            return defaultValue
        }
        guard let value = Int(raw), value > 0 else {
            throw MnemeAgentError.invalidArgument("\(name) must be a positive integer")
        }
        return value
    }

    private static func parseKinds(_ raw: String?) throws -> [SourceKind]? {
        guard let values = parseCSV(raw), !values.isEmpty else {
            return nil
        }
        return try values.map { value in
            guard let kind = SourceKind.parse(value) else {
                throw MnemeAgentError.invalidArgument("Unknown source kind: \(value)")
            }
            return kind
        }
    }

    private static func parseCSV(_ raw: String?) -> [String]? {
        guard let raw else {
            return nil
        }
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func printUsage() {
        print("""
        Usage:
          mneme search <query> [--top-k 20] [--kinds notes,code] [--source-ids id1,id2] [--json]
          mneme answer <question> [--top-k 8] [--kinds notes,code] [--source-ids id1,id2] [--json]
          mneme sources [--json]
          mneme remember <text> [--tags tag1,tag2] [--source-ref ref] [--link url] [--title title] [--json]
          mneme doctor [--json]
          mneme mcp

        Options:
          --app-support <path>  Override ~/Library/Application Support/Mneme.
        """)
    }
}

do {
    try await MnemeCLI.run()
} catch {
    FileHandle.standardError.write(Data("mneme: \(error.localizedDescription)\n".utf8))
    exit(1)
}
