import Foundation

public struct AgentTranscriptConnector: SourceConnector {
    public let root: URL
    public let sourceId: String
    public let kind: SourceKind = .agentSession
    public let includeSubagents: Bool

    public init(root: URL, sourceId: String, includeSubagents: Bool = false) {
        self.root = root
        self.sourceId = sourceId
        self.includeSubagents = includeSubagents
    }

    public func enumerate() throws -> [SourceItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [SourceItem] = []
        for case let url as URL in enumerator {
            if !includeSubagents, url.pathComponents.contains("subagents") {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "jsonl" else {
                continue
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            items.append(SourceItem(
                id: url.absoluteString,
                uri: url,
                modifiedAt: values.contentModificationDate
            ))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let content = try String(contentsOf: item.uri, encoding: .utf8)
        let parsed = AgentSessionParser.parse(jsonl: content, fileURL: item.uri)
        return ExtractedDocument(
            id: item.id,
            title: parsed.title,
            text: parsed.text,
            contentHash: ContentHash.of(parsed.text),
            meta: parsed.meta
        )
    }
}

public enum AgentLogRedactor {
    public static func redact(_ text: String) -> String {
        var value = text
        let patterns: [(String, String)] = [
            (#"sk-[A-Za-z0-9_-]{20,}"#, "[REDACTED_OPENAI_KEY]"),
            (#"ghp_[A-Za-z0-9_]{20,}"#, "[REDACTED_GITHUB_TOKEN]"),
            (#"github_pat_[A-Za-z0-9_]{20,}"#, "[REDACTED_GITHUB_TOKEN]"),
            (#"(?i)\b(api[_-]?key|token|secret|password)\b\s*[:=]\s*['"]?[^'"\s]{8,}"#, "$1=[REDACTED_SECRET]"),
            (#"\b[A-Za-z0-9+/]{48,}={0,2}\b"#, "[REDACTED_LONG_TOKEN]")
        ]
        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value
    }
}

struct ParsedAgentSession: Equatable {
    let title: String
    let text: String
    let meta: [String: String]
}

enum AgentSessionParser {
    static func parse(jsonl: String, fileURL: URL) -> ParsedAgentSession {
        var turns: [(role: String, text: String)] = []
        var meta: [String: String] = [:]

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let sessionMeta = parseSessionMeta(object) {
                meta.merge(sessionMeta) { current, _ in current }
                continue
            }

            if let turn = parseTurn(object) {
                let redacted = AgentLogRedactor.redact(turn.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !redacted.isEmpty {
                    turns.append((turn.role, redacted))
                }
            }
        }

        let text = turns
            .map { "[\($0.role)] \($0.text)" }
            .joined(separator: "\n\n")
        let title = title(meta: meta, fileURL: fileURL)
        meta["agent_log_name"] = fileURL.lastPathComponent
        return ParsedAgentSession(
            title: title,
            text: text,
            meta: meta
        )
    }

    private static func parseSessionMeta(_ object: [String: Any]) -> [String: String]? {
        guard object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        var meta: [String: String] = ["agent": "codex"]
        for key in ["id", "timestamp", "git_branch", "cli_version"] {
            if let value = payload[key] as? String, !value.isEmpty {
                meta[key == "id" ? "session_id" : key] = value
            }
        }
        if let cwd = payload["cwd"] as? String, !cwd.isEmpty {
            meta["cwd_name"] = URL(fileURLWithPath: cwd).lastPathComponent
        }
        return meta
    }

    private static func parseTurn(_ object: [String: Any]) -> (role: String, text: String)? {
        if let type = object["type"] as? String,
           ["user", "assistant"].contains(type) {
            if let message = object["message"] as? [String: Any] {
                let role = (message["role"] as? String) ?? type
                return (role, text(from: message["content"] ?? object["content"] ?? ""))
            }
            return (type, text(from: object["content"] ?? ""))
        }

        guard object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              let role = payload["role"] as? String,
              ["user", "assistant"].contains(role) else {
            return nil
        }
        return (role, text(from: payload["content"] ?? payload["text"] ?? ""))
    }

    private static func text(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let array = value as? [Any] {
            return array.map(text(from:)).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if let dictionary = value as? [String: Any] {
            for key in ["text", "content", "value"] {
                if let value = dictionary[key] {
                    let nested = text(from: value)
                    if !nested.isEmpty {
                        return nested
                    }
                }
            }
        }
        return ""
    }

    private static func title(meta: [String: String], fileURL: URL) -> String {
        let agent = meta["agent"] ?? "agent"
        if let cwdName = meta["cwd_name"], !cwdName.isEmpty {
            return "\(agent) · \(cwdName) · \(fileURL.deletingPathExtension().lastPathComponent)"
        }
        return "\(agent) · \(fileURL.deletingPathExtension().lastPathComponent)"
    }
}
