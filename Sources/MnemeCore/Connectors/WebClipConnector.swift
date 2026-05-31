import Foundation

public struct WebClipConnector: SourceConnector {
    public let root: URL
    public let sourceId: String
    public let kind: SourceKind = .web

    public init(root: URL, sourceId: String) {
        self.root = root
        self.sourceId = sourceId
    }

    public func enumerate() throws -> [SourceItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let supported = Set(["html", "htm", "md", "markdown", "txt"])
        var items: [SourceItem] = []
        for case let url as URL in enumerator {
            guard supported.contains(url.pathExtension.lowercased()) else {
                continue
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: values.contentModificationDate))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let raw = try String(contentsOf: item.uri, encoding: .utf8)
        let extracted: WebTextExtraction
        switch item.uri.pathExtension.lowercased() {
        case "html", "htm":
            extracted = HTMLTextExtractor.extract(
                raw,
                fallbackTitle: item.uri.deletingPathExtension().lastPathComponent
            )
        default:
            extracted = PlainWebTextExtractor.extract(
                raw,
                fallbackTitle: item.uri.deletingPathExtension().lastPathComponent
            )
        }
        let meta = extracted.sourceURL.map { ["source_url": $0] } ?? [:]
        return ExtractedDocument(
            id: item.id,
            title: extracted.title,
            text: extracted.text,
            contentHash: ContentHash.of(extracted.text),
            meta: meta
        )
    }
}

struct WebTextExtraction: Equatable {
    let title: String?
    let sourceURL: String?
    let text: String
}

enum HTMLTextExtractor {
    static func extract(_ raw: String, fallbackTitle: String? = nil) -> WebTextExtraction {
        let title = firstMatch(
            in: raw,
            pattern: #"<title[^>]*>(.*?)</title>"#
        ).map(cleanText) ?? fallbackTitle
        let sourceURL = canonicalURL(in: raw)

        let body = raw
            .replacingOccurrences(of: #"(?is)<script.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<nav.*?</nav>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<header.*?</header>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<footer.*?</footer>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
        return WebTextExtraction(
            title: title,
            sourceURL: sourceURL,
            text: cleanText(body)
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func canonicalURL(in raw: String) -> String? {
        for tag in tags(named: "meta", in: raw) {
            let key = (attribute("property", in: tag) ?? attribute("name", in: tag))?.lowercased()
            guard key == "og:url" || key == "canonical" else {
                continue
            }
            if let content = attribute("content", in: tag), !content.isEmpty {
                return content
            }
        }

        for tag in tags(named: "link", in: raw) {
            guard attribute("rel", in: tag)?.lowercased() == "canonical" else {
                continue
            }
            if let href = attribute("href", in: tag), !href.isEmpty {
                return href
            }
        }
        return nil
    }

    private static func tags(named name: String, in raw: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(name)\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        return regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap { match in
            guard let range = Range(match.range, in: raw) else {
                return nil
            }
            return String(raw[range])
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b\#(name)\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ),
        let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[range])
    }

    static func cleanText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PlainWebTextExtractor {
    static func extract(_ raw: String, fallbackTitle: String? = nil) -> WebTextExtraction {
        let lines = raw.components(separatedBy: .newlines)
        let title = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? fallbackTitle
        return WebTextExtraction(
            title: title,
            sourceURL: nil,
            text: HTMLTextExtractor.cleanText(raw)
        )
    }
}
