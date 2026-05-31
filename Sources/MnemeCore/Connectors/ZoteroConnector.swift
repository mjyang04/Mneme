import Foundation
import GRDB

public struct ZoteroConnector: SourceConnector {
    public let libraryRoot: URL
    public let sourceId: String
    public let cacheDir: URL
    public let kind: SourceKind = .zotero
    private let itemCache = ZoteroItemCache()

    public init(libraryRoot: URL, sourceId: String, cacheDir: URL) {
        self.libraryRoot = libraryRoot
        self.sourceId = sourceId
        self.cacheDir = cacheDir
    }

    public func enumerate() throws -> [SourceItem] {
        try cachedItems().map { item in
            SourceItem(
                id: item.documentId,
                uri: URL(string: item.documentId) ?? libraryRoot,
                modifiedAt: nil
            )
        }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        guard let zoteroItem = try cachedItems().first(where: { $0.documentId == item.id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let pdfText = zoteroItem.attachmentPath.flatMap { path -> String? in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return try? PDFTextExtractor.extract(url: url).text
        }
        let text = [
            zoteroItem.title,
            zoteroItem.creators,
            zoteroItem.year,
            zoteroItem.abstract,
            zoteroItem.tags,
            pdfText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        var meta: [String: String] = [
            "zotero_key": zoteroItem.key,
            "item_type": zoteroItem.itemType
        ]
        if let year = zoteroItem.year { meta["year"] = year }
        if let creators = zoteroItem.creators { meta["authors"] = creators }
        if let tags = zoteroItem.tags { meta["tags"] = tags }
        if let attachmentPath = zoteroItem.attachmentPath { meta["attachment_path"] = attachmentPath }

        return ExtractedDocument(
            id: zoteroItem.documentId,
            title: zoteroItem.title ?? zoteroItem.key,
            text: text,
            contentHash: ContentHash.of(text),
            meta: meta
        )
    }

    private func cachedItems() throws -> [ZoteroItem] {
        try itemCache.items {
            try loadItems()
        }
    }

    private func loadItems() throws -> [ZoteroItem] {
        let snapshot = try copyDatabaseSnapshot()
        var configuration = Configuration()
        configuration.readonly = true
        let dbQueue = try DatabaseQueue(path: snapshot.path, configuration: configuration)
        return try dbQueue.read { db in
            let deletedClause = try tableExists("deletedItems", db: db)
                ? "AND i.itemID NOT IN (SELECT itemID FROM deletedItems)"
                : ""
            let tagsExpression = try tableExists("itemTags", db: db) && tableExists("tags", db: db)
                ? """
                (SELECT GROUP_CONCAT(t.name, ', ')
                 FROM itemTags itg
                 JOIN tags t ON t.tagID = itg.tagID
                 WHERE itg.itemID = i.itemID) AS tags
                """
                : "NULL AS tags"
            let creatorsExpression = try tableExists("itemCreators", db: db) && tableExists("creators", db: db)
                ? """
                (SELECT GROUP_CONCAT(TRIM(COALESCE(c.firstName, '') || ' ' || COALESCE(c.lastName, '')), ', ')
                 FROM itemCreators ic
                 JOIN creators c ON c.creatorID = ic.creatorID
                 WHERE ic.itemID = i.itemID
                 ORDER BY ic.orderIndex) AS creators
                """
                : "NULL AS creators"
            let attachmentExpression = try tableExists("itemAttachments", db: db)
                ? """
                (SELECT ia.path
                 FROM itemAttachments ia
                 JOIN items ai ON ai.itemID = ia.itemID
                 WHERE ia.parentItemID = i.itemID AND ia.path IS NOT NULL
                 ORDER BY ai.key
                 LIMIT 1) AS attachment_path
                """
                : "NULL AS attachment_path"

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    i.key AS item_key,
                    COALESCE(it.typeName, '') AS item_type,
                    \(fieldExpression(.title)) AS title,
                    \(fieldExpression(.abstractNote)) AS abstract_note,
                    \(fieldExpression(.date)) AS item_date,
                    \(tagsExpression),
                    \(creatorsExpression),
                    \(attachmentExpression)
                FROM items i
                LEFT JOIN itemTypes it ON it.itemTypeID = i.itemTypeID
                WHERE i.key IS NOT NULL \(deletedClause)
                ORDER BY i.key
                """
            )

            return rows.map { row in
                let key: String = row["item_key"]
                let itemType: String? = row["item_type"]
                let rawAttachment: String? = row["attachment_path"]
                return ZoteroItem(
                    key: key,
                    itemType: itemType ?? "",
                    title: row["title"],
                    abstract: row["abstract_note"],
                    year: Self.year(from: row["item_date"] as String?),
                    tags: row["tags"],
                    creators: row["creators"],
                    attachmentPath: rawAttachment.flatMap(resolveAttachmentPath)
                )
            }
        }
    }

    private func copyDatabaseSnapshot() throws -> URL {
        let source = libraryRoot.appendingPathComponent("zotero.sqlite")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let destination = cacheDir.appendingPathComponent("zotero.sqlite")
        try removeSnapshotFile(destination)
        try FileManager.default.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm"] {
            let sidecarSource = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecarSource.path) else {
                continue
            }
            let sidecarDestination = URL(fileURLWithPath: destination.path + suffix)
            try removeSnapshotFile(sidecarDestination)
            try FileManager.default.copyItem(at: sidecarSource, to: sidecarDestination)
        }
        return destination
    }

    private func removeSnapshotFile(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func resolveAttachmentPath(_ raw: String) -> String? {
        if raw.hasPrefix("storage:") {
            let relative = String(raw.dropFirst("storage:".count))
            return libraryRoot
                .appendingPathComponent("storage", isDirectory: true)
                .appendingPathComponent(relative)
                .path
        }
        if raw.hasPrefix("/") {
            return raw
        }
        return nil
    }

    private func tableExists(_ name: String, db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)",
            arguments: [name]
        ) ?? false
    }

    private func fieldExpression(_ field: ZoteroField) -> String {
        """
        (SELECT v.value
         FROM itemData d
         JOIN fields f ON f.fieldID = d.fieldID
         JOIN itemDataValues v ON v.valueID = d.valueID
         WHERE d.itemID = i.itemID AND f.fieldName = '\(field.rawValue)'
         LIMIT 1)
        """
    }

    private static func year(from date: String?) -> String? {
        guard let date,
              let range = date.range(of: #"\d{4}"#, options: .regularExpression) else {
            return nil
        }
        return String(date[range])
    }
}

private final class ZoteroItemCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: [ZoteroItem]?

    func items(load: () throws -> [ZoteroItem]) throws -> [ZoteroItem] {
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = try load()
        lock.lock()
        cached = loaded
        lock.unlock()
        return loaded
    }
}

private enum ZoteroField: String {
    case title
    case abstractNote
    case date
}

private struct ZoteroItem: Equatable {
    let key: String
    let itemType: String
    let title: String?
    let abstract: String?
    let year: String?
    let tags: String?
    let creators: String?
    let attachmentPath: String?

    var documentId: String {
        "zotero://item/\(key)"
    }
}
