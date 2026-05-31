import Foundation
import MnemeCore

struct MCPServer {
    private let appSupportDirectory: URL?
    private let encoder = JSONEncoder()
    private let runtimeCache = MCPRuntimeCache()

    init(appSupportDirectory: URL?) {
        self.appSupportDirectory = appSupportDirectory
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func run() async throws {
        var buffer = Data()
        while true {
            let data = FileHandle.standardInput.availableData
            if data.isEmpty {
                break
            }
            buffer.append(data)
            while let message = extractMessage(from: &buffer) {
                guard let request = try JSONSerialization.jsonObject(with: message) as? [String: Any] else {
                    continue
                }
                if request["id"] == nil {
                    continue
                }
                let response = await handle(request)
                try write(response)
            }
        }
    }

    private func handle(_ request: [String: Any]) async -> [String: Any] {
        let id = request["id"] ?? NSNull()
        guard let method = request["method"] as? String else {
            return errorResponse(id: id, code: -32600, message: "Missing method")
        }

        do {
            switch method {
            case "initialize":
                let params = request["params"] as? [String: Any]
                let protocolVersion = params?["protocolVersion"] as? String ?? "2024-11-05"
                return successResponse(id: id, result: [
                    "protocolVersion": protocolVersion,
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "mneme", "version": "0.2.0"]
                ])
            case "tools/list":
                return successResponse(id: id, result: ["tools": toolSchemas()])
            case "tools/call":
                let result = try await callTool(params: request["params"] as? [String: Any] ?? [:])
                return successResponse(id: id, result: result)
            default:
                return errorResponse(id: id, code: -32601, message: "Unknown method: \(method)")
            }
        } catch {
            return errorResponse(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func callTool(params: [String: Any]) async throws -> [String: Any] {
        guard let name = params["name"] as? String else {
            throw MnemeAgentError.invalidArgument("tools/call missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let result: Any
        switch name {
        case "mneme.search":
            let facade = try runtimeCache.readFacade(appSupportDirectory: appSupportDirectory)
            let query = try string(arguments["query"], name: "query")
            let topK = int(arguments["topK"], defaultValue: 20)
            let searchResult = try await facade.search(
                query: query,
                topK: topK,
                kinds: try kinds(arguments["kinds"]),
                sourceIds: stringArray(arguments["sourceIds"])
            )
            result = try jsonObject(searchResult)
        case "mneme.answer":
            let facade = try runtimeCache.readFacade(appSupportDirectory: appSupportDirectory)
            let question = try string(arguments["question"], name: "question")
            let topK = int(arguments["topK"], defaultValue: 8)
            let answerResult = try await facade.answer(
                question: question,
                topK: topK,
                kinds: try kinds(arguments["kinds"]),
                sourceIds: stringArray(arguments["sourceIds"])
            )
            result = try jsonObject(answerResult)
        case "mneme.list_sources":
            let facade = try runtimeCache.readFacade(appSupportDirectory: appSupportDirectory)
            let sourcesResult = try await facade.sources()
            result = try jsonObject(sourcesResult)
        case "mneme.remember":
            let facade = try runtimeCache.writeFacade(appSupportDirectory: appSupportDirectory)
            let input = RememberInputDTO(
                text: try string(arguments["text"], name: "text"),
                tags: stringArray(arguments["tags"]),
                sourceRef: arguments["sourceRef"] as? String,
                link: arguments["link"] as? String,
                title: arguments["title"] as? String
            )
            let rememberResult = try await facade.remember(input)
            result = try jsonObject(rememberResult)
        default:
            throw MnemeAgentError.invalidArgument("Unknown tool: \(name)")
        }

        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return [
            "content": [
                ["type": "text", "text": text]
            ],
            "isError": false
        ]
    }

    private func toolSchemas() -> [[String: Any]] {
        [
            [
                "name": "mneme.search",
                "description": "Search the local Mneme index.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "topK": ["type": "integer", "default": 20],
                        "kinds": ["type": "array", "items": ["type": "string"]],
                        "sourceIds": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "mneme.answer",
                "description": "Answer from local Mneme citations using extractive offline generation.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "question": ["type": "string"],
                        "topK": ["type": "integer", "default": 8],
                        "kinds": ["type": "array", "items": ["type": "string"]],
                        "sourceIds": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["question"]
                ]
            ],
            [
                "name": "mneme.remember",
                "description": "Write a managed local memory note and index it immediately.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "tags": ["type": "array", "items": ["type": "string"]],
                        "sourceRef": ["type": "string"],
                        "link": ["type": "string"],
                        "title": ["type": "string"]
                    ],
                    "required": ["text"]
                ]
            ],
            [
                "name": "mneme.list_sources",
                "description": "List configured Mneme sources and indexed document counts.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ]
        ]
    }

    private func extractMessage(from buffer: inout Data) -> Data? {
        if buffer.starts(with: Data("Content-Length:".utf8)) {
            guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                return nil
            }
            let header = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8) ?? ""
            guard let lengthLine = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
                  let length = Int(lengthLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") else {
                buffer.removeSubrange(0..<headerRange.upperBound)
                return nil
            }
            let bodyStart = headerRange.upperBound
            let bodyEnd = bodyStart + length
            guard buffer.count >= bodyEnd else {
                return nil
            }
            let body = buffer[bodyStart..<bodyEnd]
            buffer.removeSubrange(0..<bodyEnd)
            return Data(body)
        }

        guard let newline = buffer.firstIndex(of: 0x0A) else {
            return nil
        }
        let line = buffer[..<newline]
        buffer.removeSubrange(0...newline)
        return Data(line).trimmed()
    }

    private func write(_ response: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys, .withoutEscapingSlashes])
        let header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        FileHandle.standardOutput.write(header + data)
    }

    private func successResponse(id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message]
        ]
    }

    private func string(_ value: Any?, name: String) throws -> String {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MnemeAgentError.invalidArgument("Missing required string argument: \(name)")
        }
        return value
    }

    private func int(_ value: Any?, defaultValue: Int) -> Int {
        if let value = value as? Int, value > 0 {
            return value
        }
        if let value = value as? Double, value > 0 {
            return Int(value)
        }
        return defaultValue
    }

    private func stringArray(_ value: Any?) -> [String]? {
        guard let array = value as? [String] else {
            return nil
        }
        let filtered = array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return filtered.isEmpty ? nil : filtered
    }

    private func kinds(_ value: Any?) throws -> [SourceKind]? {
        guard let values = stringArray(value) else {
            return nil
        }
        return try values.map { raw in
            guard let kind = SourceKind.parse(raw) else {
                throw MnemeAgentError.invalidArgument("Unknown source kind: \(raw)")
            }
            return kind
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}

private final class MCPRuntimeCache: @unchecked Sendable {
    private var readRuntime: QueryServiceRuntime?
    private var writeRuntime: QueryServiceRuntime?
    private let lock = NSLock()

    func readFacade(appSupportDirectory: URL?) throws -> MnemeQueryFacade {
        let runtime = try cachedReadRuntime(appSupportDirectory: appSupportDirectory)
        return MnemeQueryFacade(runtime: runtime)
    }

    func writeFacade(appSupportDirectory: URL?) throws -> MnemeQueryFacade {
        let runtime = try cachedWriteRuntime(appSupportDirectory: appSupportDirectory)
        return MnemeQueryFacade(runtime: runtime)
    }

    private func cachedReadRuntime(appSupportDirectory: URL?) throws -> QueryServiceRuntime {
        lock.lock()
        if let runtime = readRuntime ?? writeRuntime {
            lock.unlock()
            return runtime
        }
        lock.unlock()

        let runtime = try QueryServiceFactory.makeReadOnly(appSupportDirectory: appSupportDirectory)
        lock.lock()
        readRuntime = runtime
        lock.unlock()
        return runtime
    }

    private func cachedWriteRuntime(appSupportDirectory: URL?) throws -> QueryServiceRuntime {
        lock.lock()
        if let runtime = writeRuntime {
            lock.unlock()
            return runtime
        }
        lock.unlock()

        let runtime = try QueryServiceFactory.makeReadWrite(appSupportDirectory: appSupportDirectory)
        lock.lock()
        writeRuntime = runtime
        readRuntime = runtime
        lock.unlock()
        return runtime
    }
}

private extension Data {
    func trimmed() -> Data {
        var start = startIndex
        var end = endIndex
        while start < end, self[start] == 0x20 || self[start] == 0x0D || self[start] == 0x0A || self[start] == 0x09 {
            start = index(after: start)
        }
        while start < end {
            let previous = index(before: end)
            if self[previous] == 0x20 || self[previous] == 0x0D || self[previous] == 0x0A || self[previous] == 0x09 {
                end = previous
            } else {
                break
            }
        }
        return Data(self[start..<end])
    }
}
