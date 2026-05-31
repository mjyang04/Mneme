# Mneme P0+P1 — Foundation & Semantic Search MVP 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付第一个可用版本——常驻菜单栏、全局热键唤起、能对 Obsidian 笔记/PDF/代码做本地语义搜索的 macOS app。

**Architecture:** 全部核心逻辑放进可单测的 SwiftPM 包 `MnemeCore`(连接器 → 分块 → embedding → 索引 → 查询),app 壳(SwiftUI + MenuBarExtra + NSPanel 悬浮窗)在其上薄薄一层。检索用 GRDB 存向量 + 暴力余弦(sqlite-vec 留作后续优化)。embedding 默认走零配置的 `NLEmbedding`(真实语义),多语 e5 CoreML 作为收尾升级。

**Tech Stack:** Swift 5.10 / macOS 14 · SwiftPM · GRDB.swift(SQLite)· NaturalLanguage(`NLEmbedding`)· CoreML + swift-transformers(e5 升级)· SwiftUI / MenuBarExtra · KeyboardShortcuts · XCTest。

---

## 范围说明

本计划只覆盖 **P0(脚手架)+ P1(语义搜索 MVP)**,对应 [模块① spec](../01-module-index-query.md) 的搜索部分。以下**不在本计划内**,各自后续单独成计划:

- **P2** 模块①-RAG(本地 LLM 问答)
- **P3** 模块③ 活动日志
- **P4** 模块② WhisperKit 转写

本计划完成后产出可独立运行、可测试的软件:一个能索引并语义搜索本机研究材料的菜单栏 app。

### 嵌入器策略(三选一,渐进)
- `HashingEmbeddingService` — 确定性、零依赖。**仅供单测**验证管道(trigram 哈希)。
- `NLEmbeddingService` — Apple `NLEmbedding`,真实英文句向量,零模型准备。**P1 app 默认**。
- `CoreMLEmbeddingService` — multilingual-e5-small 转 CoreML,真多语 + 更高质量。**P1 收尾升级(Task 16)**,需离线转换模型,手动集成验证。

索引与某个嵌入器绑定(存 `embedder_id` + `dimension`);换嵌入器需重建索引(计划内含校验与「重建」入口)。

---

## 文件结构

```
~/Mneme/
├── Package.swift                              # SwiftPM:MnemeCore 库 + 测试
├── Sources/MnemeCore/
│   ├── Model/Types.swift                      # SourceKind, SourceItem, ExtractedDocument, Chunk, TextLocator, SearchHit, SearchFilter
│   ├── Util/ContentHash.swift                 # sha256 前缀指纹
│   ├── Util/Vector.swift                      # normalize, dotProduct, [Float]<->Data
│   ├── Chunking/Chunker.swift                 # 段落感知滑窗分块
│   ├── Embedding/EmbeddingService.swift       # 协议 + EmbedKind + EmbeddingError
│   ├── Embedding/HashingEmbeddingService.swift
│   ├── Embedding/NLEmbeddingService.swift
│   ├── Embedding/CoreMLEmbeddingService.swift # Task 16
│   ├── Index/IndexStore.swift                 # GRDB actor:迁移/upsert/delete/search
│   ├── Connectors/SourceConnector.swift       # 协议
│   ├── Connectors/NotesConnector.swift
│   ├── Connectors/PDFConnector.swift
│   ├── Connectors/CodeConnector.swift
│   ├── Pipeline/IndexingPipeline.swift
│   └── Query/QueryService.swift
├── Tests/MnemeCoreTests/
│   ├── ContentHashTests.swift
│   ├── ChunkerTests.swift
│   ├── HashingEmbeddingServiceTests.swift
│   ├── IndexStoreTests.swift
│   ├── NotesConnectorTests.swift
│   ├── PDFConnectorTests.swift
│   ├── CodeConnectorTests.swift
│   ├── IndexingPipelineTests.swift
│   ├── QueryServiceTests.swift
│   ├── EvalTests.swift
│   ├── Support/SpyEmbeddingService.swift      # 计数嵌入器(验证增量不重嵌)
│   ├── Support/PDFTestSupport.swift           # 程序化生成含文字的 PDF
│   └── Fixtures/                              # eval/queries.json 等
└── App/                                       # Xcode app(依赖 MnemeCore)
    ├── MnemeApp.swift                         # @main, MenuBarExtra + Window + Settings
    ├── AppEnvironment.swift                   # 装配 store/embedder/query/sources
    ├── Sources/SourcesStore.swift             # 用户来源(UserDefaults JSON)
    ├── Search/SearchViewModel.swift
    ├── Search/MainWindow.swift
    ├── QuickSearch/QuickSearchController.swift # NSPanel + 热键
    ├── QuickSearch/QuickSearchView.swift
    └── Settings/SettingsView.swift            # 来源管理 + 登录项 + 重建索引
```

每个文件单一职责,便于独立测试与持有上下文。`MnemeCore` 不含任何 UI / AppKit-UI 依赖(PDFKit/NaturalLanguage 属系统框架,可在库内使用)。

---

## P0 — 脚手架

### Task 1: 初始化 SwiftPM 包

**Files:**
- Create: `Package.swift`
- Create: `Sources/MnemeCore/MnemeCore.swift`(占位)
- Create: `Tests/MnemeCoreTests/SmokeTests.swift`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MnemeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MnemeCore", targets: ["MnemeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        .target(
            name: "MnemeCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "MnemeCoreTests",
            dependencies: ["MnemeCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: 写占位源文件与冒烟测试**

`Sources/MnemeCore/MnemeCore.swift`:
```swift
public enum MnemeCore {
    public static let version = "0.1.0"
}
```

`Tests/MnemeCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(MnemeCore.version, "0.1.0")
    }
}
```

- [ ] **Step 3: 建空 Fixtures 目录(避免 resources 报错)**

Run: `mkdir -p Tests/MnemeCoreTests/Fixtures && touch Tests/MnemeCoreTests/Fixtures/.gitkeep`

- [ ] **Step 4: 解析依赖并构建**

Run: `swift build`
Expected: 拉取 GRDB,`Build complete!`

- [ ] **Step 5: 跑测试**

Run: `swift test`
Expected: PASS(1 test）

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore(core): scaffold MnemeCore SwiftPM package with GRDB"
```

---

### Task 2: 领域类型 + ContentHash + 向量工具

**Files:**
- Create: `Sources/MnemeCore/Model/Types.swift`
- Create: `Sources/MnemeCore/Util/ContentHash.swift`
- Create: `Sources/MnemeCore/Util/Vector.swift`
- Test: `Tests/MnemeCoreTests/ContentHashTests.swift`
- Test: `Tests/MnemeCoreTests/VectorTests.swift`

- [ ] **Step 1: 写失败测试(ContentHash)**

`Tests/MnemeCoreTests/ContentHashTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class ContentHashTests: XCTestCase {
    func test_isDeterministic() {
        XCTAssertEqual(ContentHash.of("hello"), ContentHash.of("hello"))
    }
    func test_differsForDifferentInput() {
        XCTAssertNotEqual(ContentHash.of("hello"), ContentHash.of("world"))
    }
    func test_is16HexChars() {
        let h = ContentHash.of("anything")
        XCTAssertEqual(h.count, 16)
        XCTAssertTrue(h.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
```

- [ ] **Step 2: 写失败测试(Vector)**

`Tests/MnemeCoreTests/VectorTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class VectorTests: XCTestCase {
    func test_normalize_unitLength() {
        let v = Vector.normalize([3, 4])      // |v| = 5
        XCTAssertEqual(Vector.l2norm(v), 1.0, accuracy: 1e-5)
    }
    func test_normalize_zeroStaysZero() {
        XCTAssertEqual(Vector.normalize([0, 0]), [0, 0])
    }
    func test_dotProduct_ofNormalizedEquals1ForSame() {
        let v = Vector.normalize([1, 2, 3])
        XCTAssertEqual(Vector.dot(v, v), 1.0, accuracy: 1e-5)
    }
    func test_dataRoundTrip() {
        let v: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual([Float](data: v.data), v)
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `swift test`
Expected: FAIL(`ContentHash`/`Vector` 未定义)

- [ ] **Step 4: 写领域类型**

`Sources/MnemeCore/Model/Types.swift`:
```swift
import Foundation

public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case notes, pdf, code, transcript, activity
}

public struct SourceItem: Sendable, Equatable {
    public let id: String          // 稳定 id(通常 file:// 绝对路径)
    public let uri: URL
    public let modifiedAt: Date?
    public init(id: String, uri: URL, modifiedAt: Date?) {
        self.id = id; self.uri = uri; self.modifiedAt = modifiedAt
    }
}

public struct ExtractedDocument: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let text: String
    public let contentHash: String
    public let meta: [String: String]
    public init(id: String, title: String?, text: String,
                contentHash: String, meta: [String: String] = [:]) {
        self.id = id; self.title = title; self.text = text
        self.contentHash = contentHash; self.meta = meta
    }
}

public struct TextLocator: Codable, Equatable, Sendable {
    public var page: Int?
    public var startChar: Int?
    public var endChar: Int?
    public init(page: Int? = nil, startChar: Int? = nil, endChar: Int? = nil) {
        self.page = page; self.startChar = startChar; self.endChar = endChar
    }
}

public struct Chunk: Sendable, Equatable {
    public let ordinal: Int
    public let text: String
    public let locator: TextLocator
    public init(ordinal: Int, text: String, locator: TextLocator) {
        self.ordinal = ordinal; self.text = text; self.locator = locator
    }
}

public struct SearchFilter: Sendable, Equatable {
    public var kinds: [SourceKind]?
    public var sourceIds: [String]?
    public init(kinds: [SourceKind]? = nil, sourceIds: [String]? = nil) {
        self.kinds = kinds; self.sourceIds = sourceIds
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
}
```

- [ ] **Step 5: 写 ContentHash**

`Sources/MnemeCore/Util/ContentHash.swift`:
```swift
import Foundation
import CryptoKit

public enum ContentHash {
    /// sha256 的前 8 字节,16 个十六进制字符。
    public static func of(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 6: 写 Vector 工具**

`Sources/MnemeCore/Util/Vector.swift`:
```swift
import Foundation

public enum Vector {
    public static func l2norm(_ v: [Float]) -> Float {
        sqrt(v.reduce(0) { $0 + $1 * $1 })
    }
    public static func normalize(_ v: [Float]) -> [Float] {
        let n = l2norm(v)
        guard n > 0 else { return v }
        return v.map { $0 / n }
    }
    /// 归一化向量的点积即余弦相似度。
    public static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }
    /// 稳定哈希(FNV-1a 32-bit),跨进程一致,供 HashingEmbeddingService 用。
    public static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }
}

public extension Array where Element == Float {
    var data: Data { withUnsafeBufferPointer { Data(buffer: $0) } }
    init(data: Data) {
        self = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
```

- [ ] **Step 7: 跑测试确认通过**

Run: `swift test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/MnemeCore/Model Sources/MnemeCore/Util Tests/MnemeCoreTests/ContentHashTests.swift Tests/MnemeCoreTests/VectorTests.swift
git commit -m "feat(core): add domain types, content hash, vector utils"
```

---

## P1 — 语义搜索 MVP

### Task 3: Chunker(段落感知滑窗)

**Files:**
- Create: `Sources/MnemeCore/Chunking/Chunker.swift`
- Test: `Tests/MnemeCoreTests/ChunkerTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/ChunkerTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class ChunkerTests: XCTestCase {
    func test_shortText_singleChunk() {
        let chunks = Chunker(targetChars: 100, overlapChars: 20).chunk("hello world")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].ordinal, 0)
        XCTAssertEqual(chunks[0].text, "hello world")
        XCTAssertEqual(chunks[0].locator, TextLocator(startChar: 0, endChar: 11))
    }

    func test_longText_splitsWithOverlap() {
        let para = String(repeating: "a", count: 100)
        let text = [para, para, para].joined(separator: "\n\n") // 3 段
        let chunks = Chunker(targetChars: 120, overlapChars: 30).chunk(text)
        XCTAssertGreaterThan(chunks.count, 1)
        // 序号连续
        XCTAssertEqual(chunks.map(\.ordinal), Array(0..<chunks.count))
        // 覆盖到文本末尾
        XCTAssertEqual(chunks.last?.locator.endChar, text.count)
    }

    func test_emptyText_noChunks() {
        XCTAssertTrue(Chunker().chunk("   ").isEmpty)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter ChunkerTests`
Expected: FAIL(`Chunker` 未定义)

- [ ] **Step 3: 实现 Chunker**

`Sources/MnemeCore/Chunking/Chunker.swift`:
```swift
import Foundation

public struct Chunker {
    public let targetChars: Int
    public let overlapChars: Int

    public init(targetChars: Int = 1200, overlapChars: Int = 150) {
        precondition(overlapChars < targetChars)
        self.targetChars = targetChars
        self.overlapChars = overlapChars
    }

    /// 段落感知滑窗:优先在段落边界累积到目标长度;过长则按字符滑窗 + overlap。
    public func chunk(_ text: String) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let chars = Array(text)
        var result: [Chunk] = []
        var start = 0
        var ordinal = 0

        while start < chars.count {
            var end = min(start + targetChars, chars.count)
            // 尝试在段落/换行处收尾(向后看一个小窗,不强制)
            if end < chars.count {
                let window = max(start + targetChars - overlapChars, start + 1)
                if let brk = lastBreak(in: chars, from: window, to: end) {
                    end = brk
                }
            }
            let slice = String(chars[start..<end])
            if !slice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Chunk(
                    ordinal: ordinal,
                    text: slice,
                    locator: TextLocator(startChar: start, endChar: end)
                ))
                ordinal += 1
            }
            if end >= chars.count { break }
            start = max(end - overlapChars, start + 1)
        }
        return result
    }

    private func lastBreak(in chars: [Character], from: Int, to: Int) -> Int? {
        var i = to - 1
        while i > from {
            if chars[i] == "\n" { return i + 1 }
            i -= 1
        }
        return nil
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter ChunkerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MnemeCore/Chunking Tests/MnemeCoreTests/ChunkerTests.swift
git commit -m "feat(core): add paragraph-aware sliding-window chunker"
```

---

### Task 4: EmbeddingService 协议 + HashingEmbeddingService

**Files:**
- Create: `Sources/MnemeCore/Embedding/EmbeddingService.swift`
- Create: `Sources/MnemeCore/Embedding/HashingEmbeddingService.swift`
- Test: `Tests/MnemeCoreTests/HashingEmbeddingServiceTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/HashingEmbeddingServiceTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class HashingEmbeddingServiceTests: XCTestCase {
    func test_dimensionAndCount() async throws {
        let svc = HashingEmbeddingService(dimension: 64)
        let vecs = try await svc.embed(["abc", "def"], kind: .passage)
        XCTAssertEqual(vecs.count, 2)
        XCTAssertEqual(vecs[0].count, 64)
    }

    func test_deterministic() async throws {
        let svc = HashingEmbeddingService(dimension: 64)
        let a = try await svc.embed(["hello world"], kind: .query)
        let b = try await svc.embed(["hello world"], kind: .query)
        XCTAssertEqual(a[0], b[0])
    }

    func test_normalized() async throws {
        let svc = HashingEmbeddingService(dimension: 64)
        let v = try await svc.embed(["some longer text here"], kind: .passage)[0]
        XCTAssertEqual(Vector.l2norm(v), 1.0, accuracy: 1e-4)
    }

    func test_similarTextsCloserThanDissimilar() async throws {
        let svc = HashingEmbeddingService(dimension: 512)
        let cat   = try await svc.embed(["the cat sat on the mat"], kind: .passage)[0]
        let cat2  = try await svc.embed(["a cat sat on a mat today"], kind: .passage)[0]
        let other = try await svc.embed(["quantum chromodynamics lattice"], kind: .passage)[0]
        XCTAssertGreaterThan(Vector.dot(cat, cat2), Vector.dot(cat, other))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter HashingEmbeddingServiceTests`
Expected: FAIL(未定义)

- [ ] **Step 3: 写协议**

`Sources/MnemeCore/Embedding/EmbeddingService.swift`:
```swift
import Foundation

public enum EmbedKind: Sendable { case query, passage }

public enum EmbeddingError: Error { case modelUnavailable, dimensionMismatch }

public protocol EmbeddingService: Sendable {
    /// 稳定标识,写入索引以校验「索引与嵌入器是否匹配」。
    var id: String { get }
    var dimension: Int { get }
    func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]]
}
```

- [ ] **Step 4: 写 HashingEmbeddingService**

`Sources/MnemeCore/Embedding/HashingEmbeddingService.swift`:
```swift
import Foundation

/// 确定性的字符 trigram 哈希嵌入。仅用于测试与无模型兜底,无语义保证。
public struct HashingEmbeddingService: EmbeddingService {
    public let id: String
    public let dimension: Int

    public init(dimension: Int = 256) {
        self.id = "hashing-v1-d\(dimension)"
        self.dimension = dimension
    }

    public func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        texts.map { embedOne($0) }
    }

    private func embedOne(_ text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        let chars = Array(text.lowercased())
        if chars.count >= 3 {
            for i in 0...(chars.count - 3) {
                let gram = String(chars[i..<(i + 3)])
                let bucket = Int(Vector.fnv1a(gram) % UInt32(dimension))
                v[bucket] += 1
            }
        } else if !chars.isEmpty {
            let bucket = Int(Vector.fnv1a(String(chars)) % UInt32(dimension))
            v[bucket] += 1
        }
        return Vector.normalize(v)
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `swift test --filter HashingEmbeddingServiceTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/MnemeCore/Embedding Tests/MnemeCoreTests/HashingEmbeddingServiceTests.swift
git commit -m "feat(core): add EmbeddingService protocol + deterministic hashing embedder"
```

---

### Task 5: IndexStore(GRDB actor,暴力余弦)

> P1 用暴力余弦(加载候选向量逐一点积)。sqlite-vec KNN 是后续优化(不在本计划)。索引绑定 `embedder_id`+`dimension`,不匹配则抛错,由 app 引导「重建」。

**Files:**
- Create: `Sources/MnemeCore/Index/IndexStore.swift`
- Test: `Tests/MnemeCoreTests/IndexStoreTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/IndexStoreTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class IndexStoreTests: XCTestCase {

    private func tempPath() -> String {
        NSTemporaryDirectory() + "mneme-test-\(UUID().uuidString).sqlite"
    }

    private func upsertDoc(_ store: IndexStore, id: String, kind: SourceKind,
                           hash: String, vector: [Float]) async throws {
        try await store.upsert(
            documentId: id, sourceId: "s1", kind: kind,
            uri: URL(fileURLWithPath: "/tmp/\(id).md"),
            title: id, contentHash: hash,
            chunks: [Chunk(ordinal: 0, text: "text of \(id)",
                           locator: TextLocator(startChar: 0, endChar: 5))],
            vectors: [vector]
        )
    }

    func test_upsertAndSearch_returnsClosest() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await upsertDoc(store, id: "B", kind: .notes, hash: "h2", vector: [0, 1, 0])

        let hits = try await store.search([0.9, 0.1, 0], topK: 1, filter: nil)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].documentId, "A")
        XCTAssertEqual(hits[0].kind, .notes)
    }

    func test_incrementalUpsert_isIdempotent() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        let count = try await store.documentCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try await store.documentHash(id: "A"), "h1")
    }

    func test_deleteDocument_cascades() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await store.deleteDocument(id: "A")
        let hits = try await store.search([1, 0, 0], topK: 5, filter: nil)
        XCTAssertTrue(hits.isEmpty)
        XCTAssertNil(try await store.documentHash(id: "A"))
    }

    func test_filterByKind() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await upsertDoc(store, id: "B", kind: .pdf,   hash: "h2", vector: [1, 0, 0])
        let hits = try await store.search([1, 0, 0], topK: 5,
                                          filter: SearchFilter(kinds: [.pdf]))
        XCTAssertEqual(hits.map(\.documentId), ["B"])
    }

    func test_configMismatch_throws() async throws {
        let path = tempPath()
        let store = try IndexStore(path: path, embedderId: "a", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        XCTAssertThrowsError(try IndexStore(path: path, embedderId: "b", dimension: 3))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter IndexStoreTests`
Expected: FAIL(`IndexStore` 未定义)

- [ ] **Step 3: 实现 IndexStore**

`Sources/MnemeCore/Index/IndexStore.swift`:
```swift
import Foundation
import GRDB

public actor IndexStore {
    private let dbQueue: DatabaseQueue
    public let embedderId: String
    public let dimension: Int

    /// - path: nil = 内存库(测试用);否则磁盘路径。
    public init(path: String?, embedderId: String, dimension: Int) throws {
        self.dbQueue = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        self.embedderId = embedderId
        self.dimension = dimension
        try dbQueue.write { db in
            try Self.createSchema(db)
            try Self.ensureConfig(db, embedderId: embedderId, dimension: dimension)
        }
    }

    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS documents (
              id TEXT PRIMARY KEY, source_id TEXT NOT NULL, uri TEXT NOT NULL,
              title TEXT, content_hash TEXT NOT NULL, kind_raw TEXT NOT NULL,
              indexed_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS chunks (
              id TEXT PRIMARY KEY, document_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
              text TEXT NOT NULL, locator_json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS chunk_vec (
              chunk_id TEXT PRIMARY KEY, embedding BLOB NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(document_id);
            """)
    }

    private static func ensureConfig(_ db: Database, embedderId: String, dimension: Int) throws {
        let existing = try Row.fetchAll(db, sql: "SELECT key, value FROM config")
            .reduce(into: [String: String]()) { $0[$1["key"]] = $1["value"] }
        if let eid = existing["embedder_id"] {
            guard eid == embedderId, existing["dimension"] == String(dimension) else {
                throw EmbeddingError.dimensionMismatch
            }
        } else {
            try db.execute(sql: "INSERT INTO config(key,value) VALUES('embedder_id',?),('dimension',?)",
                           arguments: [embedderId, String(dimension)])
        }
    }

    public func documentHash(id: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT content_hash FROM documents WHERE id = ?",
                                arguments: [id])
        }
    }

    public func documentCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
        }
    }

    public func deleteDocument(id: String) throws {
        try dbQueue.write { db in
            try Self.deleteChunks(db, documentId: id)
            try db.execute(sql: "DELETE FROM documents WHERE id = ?", arguments: [id])
        }
    }

    private static func deleteChunks(_ db: Database, documentId: String) throws {
        try db.execute(sql: """
            DELETE FROM chunk_vec WHERE chunk_id IN
              (SELECT id FROM chunks WHERE document_id = ?)
            """, arguments: [documentId])
        try db.execute(sql: "DELETE FROM chunks WHERE document_id = ?", arguments: [documentId])
    }

    public func upsert(documentId: String, sourceId: String, kind: SourceKind, uri: URL,
                       title: String?, contentHash: String,
                       chunks: [Chunk], vectors: [[Float]]) throws {
        precondition(chunks.count == vectors.count)
        let encoder = JSONEncoder()
        try dbQueue.write { db in
            try Self.deleteChunks(db, documentId: documentId)
            try db.execute(sql: """
                INSERT INTO documents(id, source_id, uri, title, content_hash, kind_raw, indexed_at)
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                  source_id=excluded.source_id, uri=excluded.uri, title=excluded.title,
                  content_hash=excluded.content_hash, kind_raw=excluded.kind_raw,
                  indexed_at=excluded.indexed_at
                """, arguments: [documentId, sourceId, uri.absoluteString, title,
                                 contentHash, kind.rawValue, Date().timeIntervalSince1970])
            for (chunk, vector) in zip(chunks, vectors) {
                let chunkId = "\(documentId)#\(chunk.ordinal)"
                let locatorJSON = String(data: try encoder.encode(chunk.locator), encoding: .utf8)!
                try db.execute(sql: """
                    INSERT INTO chunks(id, document_id, ordinal, text, locator_json)
                    VALUES(?,?,?,?,?)
                    """, arguments: [chunkId, documentId, chunk.ordinal, chunk.text, locatorJSON])
                try db.execute(sql: "INSERT INTO chunk_vec(chunk_id, embedding) VALUES(?,?)",
                               arguments: [chunkId, vector.data])
            }
        }
    }

    public func search(_ queryVector: [Float], topK: Int, filter: SearchFilter?) throws -> [SearchHit] {
        guard queryVector.count == dimension else { throw EmbeddingError.dimensionMismatch }
        let decoder = JSONDecoder()
        var sql = """
            SELECT v.chunk_id AS chunk_id, c.document_id AS document_id, c.text AS text,
                   c.locator_json AS locator_json, v.embedding AS embedding,
                   d.title AS title, d.uri AS uri, d.kind_raw AS kind_raw
            FROM chunk_vec v
            JOIN chunks c ON c.id = v.chunk_id
            JOIN documents d ON d.id = c.document_id
            """
        var args: [DatabaseValueConvertible] = []
        var clauses: [String] = []
        if let kinds = filter?.kinds, !kinds.isEmpty {
            clauses.append("d.kind_raw IN (\(kinds.map { _ in "?" }.joined(separator: ",")))")
            args.append(contentsOf: kinds.map { $0.rawValue })
        }
        if let sids = filter?.sourceIds, !sids.isEmpty {
            clauses.append("d.source_id IN (\(sids.map { _ in "?" }.joined(separator: ",")))")
            args.append(contentsOf: sids)
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            var scored: [(SearchHit, Float)] = []
            scored.reserveCapacity(rows.count)
            for row in rows {
                let emb = [Float](data: row["embedding"])
                let score = Vector.dot(queryVector, emb)
                let locator = (row["locator_json"] as String?)
                    .flatMap { try? decoder.decode(TextLocator.self, from: Data($0.utf8)) }
                let hit = SearchHit(
                    chunkId: row["chunk_id"], documentId: row["document_id"],
                    score: score, text: row["text"], title: row["title"],
                    uri: URL(string: row["uri"]) ?? URL(fileURLWithPath: row["uri"]),
                    kind: SourceKind(rawValue: row["kind_raw"]) ?? .notes,
                    locator: locator)
                scored.append((hit, score))
            }
            return scored.sorted { $0.1 > $1.1 }.prefix(topK).map(\.0)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter IndexStoreTests`
Expected: PASS(5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/MnemeCore/Index Tests/MnemeCoreTests/IndexStoreTests.swift
git commit -m "feat(core): add GRDB-backed IndexStore with brute-force cosine search"
```

---

### Task 6: SourceConnector 协议 + NotesConnector

> 连接器的 `enumerate`/`extract` 为同步 `throws`(文件 IO);异步的是 embedding。Pipeline 在后台任务里调用它们。

**Files:**
- Create: `Sources/MnemeCore/Connectors/SourceConnector.swift`
- Create: `Sources/MnemeCore/Connectors/NotesConnector.swift`
- Test: `Tests/MnemeCoreTests/NotesConnectorTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/NotesConnectorTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class NotesConnectorTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)
        try fm.createDirectory(at: vault.appendingPathComponent(".obsidian"),
                               withIntermediateDirectories: true)
        try "---\ntitle: My Note\ntags: ai\n---\n# Heading\nsome content here"
            .write(to: vault.appendingPathComponent("note1.md"), atomically: true, encoding: .utf8)
        try "just plain text, no frontmatter"
            .write(to: vault.appendingPathComponent("note2.md"), atomically: true, encoding: .utf8)
        try "should be ignored"
            .write(to: vault.appendingPathComponent(".obsidian/app.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func test_enumerate_skipsObsidianDir() throws {
        let c = NotesConnector(root: vault, sourceId: "s1")
        XCTAssertEqual(try c.enumerate().count, 2)
    }

    func test_extract_parsesFrontmatterAndTitle() throws {
        let c = NotesConnector(root: vault, sourceId: "s1")
        let item = try c.enumerate().first { $0.uri.lastPathComponent == "note1.md" }!
        let doc = try c.extract(item)
        XCTAssertEqual(doc.title, "My Note")
        XCTAssertEqual(doc.meta["tags"], "ai")
        XCTAssertTrue(doc.text.contains("some content here"))
        XCTAssertFalse(doc.text.contains("---"))
    }

    func test_extract_fallsBackToFilenameTitle() throws {
        let c = NotesConnector(root: vault, sourceId: "s1")
        let item = try c.enumerate().first { $0.uri.lastPathComponent == "note2.md" }!
        XCTAssertEqual(try c.extract(item).title, "note2")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter NotesConnectorTests`
Expected: FAIL(未定义)

- [ ] **Step 3: 写协议**

`Sources/MnemeCore/Connectors/SourceConnector.swift`:
```swift
import Foundation

public protocol SourceConnector: Sendable {
    var sourceId: String { get }
    var kind: SourceKind { get }
    func enumerate() throws -> [SourceItem]
    func extract(_ item: SourceItem) throws -> ExtractedDocument
}
```

- [ ] **Step 4: 写 NotesConnector**

`Sources/MnemeCore/Connectors/NotesConnector.swift`:
```swift
import Foundation

public struct NotesConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .notes
    private let root: URL

    public init(root: URL, sourceId: String) {
        self.root = root; self.sourceId = sourceId
    }

    public func enumerate() throws -> [SourceItem] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var items: [SourceItem] = []
        for case let url as URL in en {
            guard url.pathExtension.lowercased() == "md" else { continue }
            if url.path.contains("/.obsidian/") || url.path.contains("/.trash/") { continue }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: mod))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let raw = try String(contentsOf: item.uri, encoding: .utf8)
        var body = raw
        var meta: [String: String] = [:]
        if raw.hasPrefix("---\n") {
            let rest = raw.dropFirst(4)
            if let close = rest.range(of: "\n---") {
                for line in rest[rest.startIndex..<close.lowerBound].split(separator: "\n") {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty { meta[key] = value }
                }
                body = String(rest[close.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let title = meta["title"] ?? firstHeading(in: body)
            ?? item.uri.deletingPathExtension().lastPathComponent
        return ExtractedDocument(id: item.id, title: title, text: body,
                                 contentHash: ContentHash.of(body), meta: meta)
    }

    private func firstHeading(in body: String) -> String? {
        for line in body.split(separator: "\n") where line.hasPrefix("# ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `swift test --filter NotesConnectorTests`
Expected: PASS(3 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/MnemeCore/Connectors Tests/MnemeCoreTests/NotesConnectorTests.swift
git commit -m "feat(core): add SourceConnector protocol + Obsidian NotesConnector"
```

---

### Task 7: PDFConnector(PDFKit + Vision OCR 兜底)

> P1 locator 仅记 charRange(不做页级精确跳转);文本型 PDF 走 PDFKit,空白页走 Vision OCR(best-effort,无单测,见手动验证)。

**Files:**
- Create: `Sources/MnemeCore/Connectors/PDFConnector.swift`
- Create: `Tests/MnemeCoreTests/Support/PDFTestSupport.swift`
- Test: `Tests/MnemeCoreTests/PDFConnectorTests.swift`

- [ ] **Step 1: 写测试支撑(程序化生成含文字 PDF)**

`Tests/MnemeCoreTests/Support/PDFTestSupport.swift`:
```swift
import Foundation
import AppKit

enum PDFTestSupport {
    static func makeTextPDF(_ text: String, at url: URL) throws {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        ctx.beginPDFPage(nil)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            .draw(in: CGRect(x: 50, y: 50, width: 500, height: 700))
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        data.write(to: url, atomically: true)
    }
}
```

- [ ] **Step 2: 写失败测试**

`Tests/MnemeCoreTests/PDFConnectorTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class PDFConnectorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("papers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try PDFTestSupport.makeTextPDF("retrieval augmented generation for research",
                                       at: dir.appendingPathComponent("paper.pdf"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func test_enumerate_findsPDFs() throws {
        XCTAssertEqual(try PDFConnector(root: dir, sourceId: "p1").enumerate().count, 1)
    }

    func test_extract_pullsText() throws {
        let c = PDFConnector(root: dir, sourceId: "p1")
        let doc = try c.extract(c.enumerate()[0])
        XCTAssertTrue(doc.text.contains("retrieval augmented generation"))
        XCTAssertEqual(doc.title, "paper")
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `swift test --filter PDFConnectorTests`
Expected: FAIL(`PDFConnector` 未定义)

- [ ] **Step 4: 实现 PDFConnector**

`Sources/MnemeCore/Connectors/PDFConnector.swift`:
```swift
import Foundation
import PDFKit
#if canImport(Vision)
import Vision
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct PDFConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .pdf
    private let root: URL

    public init(root: URL, sourceId: String) { self.root = root; self.sourceId = sourceId }

    public func enumerate() throws -> [SourceItem] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var items: [SourceItem] = []
        for case let url as URL in en where url.pathExtension.lowercased() == "pdf" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: mod))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        guard let pdf = PDFDocument(url: item.uri) else { throw CocoaError(.fileReadCorruptFile) }
        var parts: [String] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let text = page.string ?? ""
            parts.append(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ocr(page: page) : text)
        }
        let body = parts.joined(separator: "\n\n")
        let title = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? item.uri.deletingPathExtension().lastPathComponent
        return ExtractedDocument(id: item.id, title: title, text: body,
                                 contentHash: ContentHash.of(body),
                                 meta: ["pages": String(pdf.pageCount)])
    }

    private func ocr(page: PDFPage) -> String {
        #if canImport(Vision) && canImport(AppKit)
        let bounds = page.bounds(for: .mediaBox)
        let img = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2),
                                 for: .mediaBox)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        #else
        return ""
        #endif
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `swift test --filter PDFConnectorTests`
Expected: PASS(2 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/MnemeCore/Connectors/PDFConnector.swift Tests/MnemeCoreTests/PDFConnectorTests.swift Tests/MnemeCoreTests/Support/PDFTestSupport.swift
git commit -m "feat(core): add PDFConnector (PDFKit text + Vision OCR fallback)"
```

---

### Task 8: CodeConnector(忽略规则)

**Files:**
- Create: `Sources/MnemeCore/Connectors/CodeConnector.swift`
- Test: `Tests/MnemeCoreTests/CodeConnectorTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/CodeConnectorTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class CodeConnectorTests: XCTestCase {
    private var repo: URL!

    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repo-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: repo.appendingPathComponent("node_modules"),
                               withIntermediateDirectories: true)
        try "func main() { print(\"hi\") }"
            .write(to: repo.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "module.exports = {}"
            .write(to: repo.appendingPathComponent("node_modules/lib.js"),
                   atomically: true, encoding: .utf8)
        try "binary-ish".write(to: repo.appendingPathComponent("data.bin"),
                               atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo) }

    func test_enumerate_skipsIgnoredDirsAndNonCode() throws {
        let items = try CodeConnector(root: repo, sourceId: "c1").enumerate()
        XCTAssertEqual(items.map { $0.uri.lastPathComponent }, ["main.swift"])
    }

    func test_extract_setsLanguageMeta() throws {
        let c = CodeConnector(root: repo, sourceId: "c1")
        let doc = try c.extract(c.enumerate()[0])
        XCTAssertEqual(doc.meta["language"], "swift")
        XCTAssertTrue(doc.text.contains("func main"))
        XCTAssertEqual(doc.title, "main.swift")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter CodeConnectorTests`
Expected: FAIL(未定义)

- [ ] **Step 3: 实现 CodeConnector**

`Sources/MnemeCore/Connectors/CodeConnector.swift`:
```swift
import Foundation

public struct CodeConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .code
    private let root: URL
    private let ignoredDirs: Set<String>
    private let codeExtensions: Set<String>

    public init(root: URL, sourceId: String,
                ignoredDirs: Set<String> = ["node_modules", ".git", "build", ".build",
                                            "outputs", "dist", ".venv", "__pycache__",
                                            "DerivedData", "qdrant_storage"],
                codeExtensions: Set<String> = ["swift", "py", "js", "ts", "tsx", "jsx",
                                               "go", "rs", "c", "cpp", "h", "hpp", "java",
                                               "rb", "sh", "yaml", "yml", "toml"]) {
        self.root = root; self.sourceId = sourceId
        self.ignoredDirs = ignoredDirs; self.codeExtensions = codeExtensions
    }

    public func enumerate() throws -> [SourceItem] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var items: [SourceItem] = []
        for case let url as URL in en {
            let components = Set(url.pathComponents)
            if !components.isDisjoint(with: ignoredDirs) { continue }
            guard codeExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: mod))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let text = try String(contentsOf: item.uri, encoding: .utf8)
        let ext = item.uri.pathExtension.lowercased()
        return ExtractedDocument(id: item.id, title: item.uri.lastPathComponent, text: text,
                                 contentHash: ContentHash.of(text), meta: ["language": ext])
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter CodeConnectorTests`
Expected: PASS(2 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/MnemeCore/Connectors/CodeConnector.swift Tests/MnemeCoreTests/CodeConnectorTests.swift
git commit -m "feat(core): add CodeConnector with ignore rules"
```

---

### Task 9: IndexingPipeline(增量编排)

**Files:**
- Create: `Sources/MnemeCore/Pipeline/IndexingPipeline.swift`
- Create: `Tests/MnemeCoreTests/Support/SpyEmbeddingService.swift`
- Test: `Tests/MnemeCoreTests/IndexingPipelineTests.swift`

- [ ] **Step 1: 写计数嵌入器(测试支撑)**

`Tests/MnemeCoreTests/Support/SpyEmbeddingService.swift`:
```swift
import Foundation
@testable import MnemeCore

final class SpyEmbeddingService: EmbeddingService, @unchecked Sendable {
    let base: EmbeddingService
    private let lock = NSLock()
    private(set) var totalTextsEmbedded = 0

    init(base: EmbeddingService) { self.base = base }
    var id: String { base.id }
    var dimension: Int { base.dimension }

    func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        lock.lock(); totalTextsEmbedded += texts.count; lock.unlock()
        return try await base.embed(texts, kind: kind)
    }
}
```

- [ ] **Step 2: 写失败测试**

`Tests/MnemeCoreTests/IndexingPipelineTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class IndexingPipelineTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "deep learning and neural networks"
            .write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "italian pasta recipes and tomato sauce"
            .write(to: vault.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: vault) }

    private func makePipeline() throws -> (IndexingPipeline, IndexStore, SpyEmbeddingService) {
        let embedder = SpyEmbeddingService(base: HashingEmbeddingService(dimension: 64))
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: 64)
        let pipeline = IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder, store: store)
        return (pipeline, store, embedder)
    }

    func test_run_indexesAllDocuments() async throws {
        let (pipeline, store, _) = try makePipeline()
        let stats = try await pipeline.run()
        XCTAssertEqual(stats.indexed, 2)
        XCTAssertEqual(try await store.documentCount(), 2)
    }

    func test_secondRun_skipsUnchanged_noReembed() async throws {
        let (pipeline, _, spy) = try makePipeline()
        _ = try await pipeline.run()
        let embeddedAfterFirst = spy.totalTextsEmbedded
        let stats = try await pipeline.run()
        XCTAssertEqual(stats.indexed, 0)
        XCTAssertEqual(stats.skipped, 2)
        XCTAssertEqual(spy.totalTextsEmbedded, embeddedAfterFirst) // 未重新嵌入
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `swift test --filter IndexingPipelineTests`
Expected: FAIL(`IndexingPipeline` 未定义)

- [ ] **Step 4: 实现 IndexingPipeline**

`Sources/MnemeCore/Pipeline/IndexingPipeline.swift`:
```swift
import Foundation

public struct IndexRunStats: Sendable, Equatable {
    public var indexed = 0
    public var skipped = 0
    public var failed = 0
}

public actor IndexingPipeline {
    private let connectors: [SourceConnector]
    private let embedder: EmbeddingService
    private let store: IndexStore
    private let chunker: Chunker

    public init(connectors: [SourceConnector], embedder: EmbeddingService,
                store: IndexStore, chunker: Chunker = Chunker()) {
        self.connectors = connectors; self.embedder = embedder
        self.store = store; self.chunker = chunker
    }

    /// 跑一遍全部连接器,按 contentHash 增量跳过未变文档。
    public func run(progress: (@Sendable (String) -> Void)? = nil) async throws -> IndexRunStats {
        var stats = IndexRunStats()
        for connector in connectors {
            let items = try connector.enumerate()
            for item in items {
                do {
                    let doc = try connector.extract(item)
                    if try await store.documentHash(id: doc.id) == doc.contentHash {
                        stats.skipped += 1; continue
                    }
                    let chunks = chunker.chunk(doc.text)
                    guard !chunks.isEmpty else { stats.skipped += 1; continue }
                    let vectors = try await embedder.embed(chunks.map(\.text), kind: .passage)
                    try await store.upsert(
                        documentId: doc.id, sourceId: connector.sourceId, kind: connector.kind,
                        uri: item.uri, title: doc.title, contentHash: doc.contentHash,
                        chunks: chunks, vectors: vectors)
                    stats.indexed += 1
                } catch {
                    stats.failed += 1
                    progress?("索引失败 \(item.uri.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return stats
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `swift test --filter IndexingPipelineTests`
Expected: PASS(2 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/MnemeCore/Pipeline Tests/MnemeCoreTests/IndexingPipelineTests.swift Tests/MnemeCoreTests/Support/SpyEmbeddingService.swift
git commit -m "feat(core): add incremental IndexingPipeline"
```

---

### Task 10: QueryService(检索 + 文档级去重)

**Files:**
- Create: `Sources/MnemeCore/Query/QueryService.swift`
- Test: `Tests/MnemeCoreTests/QueryServiceTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/QueryServiceTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class QueryServiceTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "deep learning neural networks gradient descent backpropagation"
            .write(to: vault.appendingPathComponent("ml.md"), atomically: true, encoding: .utf8)
        try "italian pasta tomato basil parmesan recipe kitchen"
            .write(to: vault.appendingPathComponent("food.md"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: vault) }

    private func makeIndexed() async throws -> QueryService {
        let embedder = HashingEmbeddingService(dimension: 512)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: 512)
        let pipeline = IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder, store: store)
        _ = try await pipeline.run()
        return QueryService(embedder: embedder, store: store)
    }

    func test_search_returnsRelevantDocFirst() async throws {
        let q = try await makeIndexed()
        let hits = try await q.search("neural network gradient learning", topK: 5)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits[0].uri.lastPathComponent, "ml.md")
    }

    func test_emptyQuery_returnsEmpty() async throws {
        let q = try await makeIndexed()
        XCTAssertTrue(try await q.search("   ").isEmpty)
    }

    func test_collapseByDocument_keepsBestPerDoc() {
        let url = URL(fileURLWithPath: "/x.md")
        func hit(_ doc: String, _ score: Float) -> SearchHit {
            SearchHit(chunkId: "\(doc)#\(score)", documentId: doc, score: score,
                      text: "t", title: doc, uri: url, kind: .notes, locator: nil)
        }
        let collapsed = QueryService.collapseByDocument(
            [hit("A", 0.3), hit("A", 0.9), hit("B", 0.5)], topK: 10)
        XCTAssertEqual(collapsed.map(\.documentId), ["A", "B"])
        XCTAssertEqual(collapsed[0].score, 0.9)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter QueryServiceTests`
Expected: FAIL(`QueryService` 未定义)

- [ ] **Step 3: 实现 QueryService**

`Sources/MnemeCore/Query/QueryService.swift`:
```swift
import Foundation

public struct QueryService: Sendable {
    private let embedder: EmbeddingService
    private let store: IndexStore

    public init(embedder: EmbeddingService, store: IndexStore) {
        self.embedder = embedder; self.store = store
    }

    public func search(_ text: String, topK: Int = 20,
                       filter: SearchFilter? = nil) async throws -> [SearchHit] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let qvec = try await embedder.embed([trimmed], kind: .query)[0]
        let raw = try await store.search(qvec, topK: topK * 4, filter: filter)
        return Self.collapseByDocument(raw, topK: topK)
    }

    /// 同一文档多 chunk 命中只保留最高分,再取 topK。
    static func collapseByDocument(_ hits: [SearchHit], topK: Int) -> [SearchHit] {
        var best: [String: SearchHit] = [:]
        for h in hits {
            if let cur = best[h.documentId], cur.score >= h.score { continue }
            best[h.documentId] = h
        }
        return Array(best.values.sorted { $0.score > $1.score }.prefix(topK))
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter QueryServiceTests`
Expected: PASS(3 tests)

- [ ] **Step 5: 跑全部核心测试**

Run: `swift test`
Expected: 全部 PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/MnemeCore/Query Tests/MnemeCoreTests/QueryServiceTests.swift
git commit -m "feat(core): add QueryService with document-level dedup"
```

---

### Task 11: NLEmbeddingService(零配置真实语义,app 默认)

> Apple `NLEmbedding` 句向量,无需下载/转换模型,真实(中等)英文语义。多语 + 更高质量留给 Task 17 的 CoreML e5。

**Files:**
- Create: `Sources/MnemeCore/Embedding/NLEmbeddingService.swift`
- Test: `Tests/MnemeCoreTests/NLEmbeddingServiceTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/MnemeCoreTests/NLEmbeddingServiceTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class NLEmbeddingServiceTests: XCTestCase {
    func test_dimensionPositive_andNormalized() async throws {
        let svc = try NLEmbeddingService()
        XCTAssertGreaterThan(svc.dimension, 0)
        let v = try await svc.embed(["machine learning"], kind: .passage)[0]
        XCTAssertEqual(v.count, svc.dimension)
        XCTAssertEqual(Vector.l2norm(v), 1.0, accuracy: 1e-3)
    }

    func test_emptyString_zeroVector() async throws {
        let svc = try NLEmbeddingService()
        let v = try await svc.embed([""], kind: .passage)[0]
        XCTAssertEqual(Vector.l2norm(v), 0.0, accuracy: 1e-6)
    }

    // 依赖系统句向量模型;语义排序断言为软验证。
    func test_semanticOrdering() async throws {
        let svc = try NLEmbeddingService()
        let dog = try await svc.embed(["dog"], kind: .query)[0]
        let puppy = try await svc.embed(["puppy"], kind: .passage)[0]
        let econ = try await svc.embed(["macroeconomic policy"], kind: .passage)[0]
        XCTAssertGreaterThan(Vector.dot(dog, puppy), Vector.dot(dog, econ))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter NLEmbeddingServiceTests`
Expected: FAIL(`NLEmbeddingService` 未定义)

- [ ] **Step 3: 实现 NLEmbeddingService**

`Sources/MnemeCore/Embedding/NLEmbeddingService.swift`:
```swift
import Foundation
import NaturalLanguage

public struct NLEmbeddingService: EmbeddingService {
    public let id = "nl-sentence-en-v1"
    public let dimension: Int
    private let embedding: NLEmbedding

    public init(language: NLLanguage = .english) throws {
        guard let e = NLEmbedding.sentenceEmbedding(for: language) else {
            throw EmbeddingError.modelUnavailable
        }
        self.embedding = e
        self.dimension = e.dimension
    }

    public func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        texts.map { text in
            guard let v = embedding.vector(for: text) else {
                return [Float](repeating: 0, count: dimension)
            }
            return Vector.normalize(v.map { Float($0) })
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter NLEmbeddingServiceTests`
Expected: PASS(3 tests;若机器无英文句向量模型,`test_semanticOrdering` 可能需放宽——见注释)

- [ ] **Step 5: Commit**

```bash
git add Sources/MnemeCore/Embedding/NLEmbeddingService.swift Tests/MnemeCoreTests/NLEmbeddingServiceTests.swift
git commit -m "feat(core): add NLEmbedding-based embedding service (app default)"
```

---

### Task 12: 检索评测 harness(Hit@k / MRR)

**Files:**
- Create: `Sources/MnemeCore/Eval/RetrievalEval.swift`
- Test: `Tests/MnemeCoreTests/EvalTests.swift`

- [ ] **Step 1: 写失败测试(度量函数 + 端到端)**

`Tests/MnemeCoreTests/EvalTests.swift`:
```swift
import XCTest
@testable import MnemeCore

final class EvalTests: XCTestCase {
    func test_hitAtK() {
        XCTAssertFalse(RetrievalEval.hitAtK(ranked: ["A", "B", "C"], relevant: ["C"], k: 2))
        XCTAssertTrue(RetrievalEval.hitAtK(ranked: ["A", "B", "C"], relevant: ["C"], k: 3))
    }
    func test_reciprocalRank() {
        XCTAssertEqual(RetrievalEval.reciprocalRank(ranked: ["A", "B"], relevant: ["B"]), 0.5)
        XCTAssertEqual(RetrievalEval.reciprocalRank(ranked: ["A", "B"], relevant: ["Z"]), 0.0)
    }
    func test_aggregate_meansAcrossQueries() {
        let agg = RetrievalEval.aggregate([
            (ranked: ["A", "B"], relevant: ["A"]),   // hit@2=1, rr=1.0
            (ranked: ["A", "B"], relevant: ["B"])    // hit@2=1, rr=0.5
        ], k: 2)
        XCTAssertEqual(agg.hitAtK, 1.0, accuracy: 1e-9)
        XCTAssertEqual(agg.mrr, 0.75, accuracy: 1e-9)
    }

    func test_endToEnd_evalOverFixtureVault() async throws {
        let vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let docs = [
            "ml.md": "deep learning neural networks gradient descent backpropagation training",
            "food.md": "italian pasta tomato basil parmesan recipe kitchen cooking",
            "stats.md": "probability distribution variance expectation random sampling statistics"
        ]
        for (name, body) in docs {
            try body.write(to: vault.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let embedder = HashingEmbeddingService(dimension: 512)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: 512)
        _ = try await IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder, store: store).run()
        let query = QueryService(embedder: embedder, store: store)

        func docId(_ name: String) -> String { vault.appendingPathComponent(name).absoluteString }
        let cases: [(q: String, expect: String)] = [
            ("neural network gradient learning", "ml.md"),
            ("pasta tomato recipe cooking", "food.md"),
            ("probability variance sampling", "stats.md")
        ]
        var rankings: [(ranked: [String], relevant: Set<String>)] = []
        for c in cases {
            let hits = try await query.search(c.q, topK: 5)
            rankings.append((ranked: hits.map(\.documentId), relevant: [docId(c.expect)]))
        }
        let agg = RetrievalEval.aggregate(rankings, k: 5)
        XCTAssertGreaterThanOrEqual(agg.hitAtK, 0.9)
        XCTAssertGreaterThanOrEqual(agg.mrr, 0.8)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter EvalTests`
Expected: FAIL(`RetrievalEval` 未定义)

- [ ] **Step 3: 实现 RetrievalEval**

`Sources/MnemeCore/Eval/RetrievalEval.swift`:
```swift
import Foundation

public enum RetrievalEval {
    public static func hitAtK(ranked: [String], relevant: Set<String>, k: Int) -> Bool {
        ranked.prefix(k).contains { relevant.contains($0) }
    }

    public static func reciprocalRank(ranked: [String], relevant: Set<String>) -> Double {
        for (i, id) in ranked.enumerated() where relevant.contains(id) {
            return 1.0 / Double(i + 1)
        }
        return 0
    }

    public struct Aggregate: Equatable, Sendable {
        public let hitAtK: Double
        public let mrr: Double
    }

    public static func aggregate(
        _ rankings: [(ranked: [String], relevant: Set<String>)], k: Int
    ) -> Aggregate {
        guard !rankings.isEmpty else { return Aggregate(hitAtK: 0, mrr: 0) }
        let hits = rankings.map { hitAtK(ranked: $0.ranked, relevant: $0.relevant, k: k) ? 1.0 : 0.0 }
        let rrs = rankings.map { reciprocalRank(ranked: $0.ranked, relevant: $0.relevant) }
        return Aggregate(hitAtK: hits.reduce(0, +) / Double(hits.count),
                         mrr: rrs.reduce(0, +) / Double(rrs.count))
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter EvalTests`
Expected: PASS(4 tests)

- [ ] **Step 5: 跑全部核心测试(P0+P1 核心收尾)**

Run: `swift test`
Expected: 全部 PASS。至此 `MnemeCore` 全链路(连接器→分块→嵌入→索引→检索→评测)完成且可测。

- [ ] **Step 6: Commit**

```bash
git add Sources/MnemeCore/Eval Tests/MnemeCoreTests/EvalTests.swift
git commit -m "feat(core): add retrieval eval harness (Hit@k / MRR)"
```

---

## P1 — App 壳层(SwiftUI;非单测,构建 + 手动冒烟)

> 以下任务产出真实可交互的 app。UI/AppKit 不做单测;每个任务的验证 = Xcode 构建通过 + 明确的手动冒烟步骤。`MnemeCore` 已被前 12 个任务充分覆盖。

### Task 13: Xcode app 脚手架 + 装配

**Files:**
- 在 Xcode 中创建 macOS App target `Mneme`(非沙箱),依赖本地包 `MnemeCore`
- Create: `App/MnemeApp.swift`
- Create: `App/AppEnvironment.swift`
- Create: `App/Sources/SourcesStore.swift`
- Create: `App/MenuBarContent.swift`

- [ ] **Step 1: 在 Xcode 建 app target**

手动步骤:
1. Xcode → File → New → Project → macOS → App,名称 `Mneme`,Interface SwiftUI,Language Swift,保存到 `~/Mneme/`(与 `Package.swift` 同级,app 代码放 `App/`)。
2. 选中 Mneme target → Signing & Capabilities → **移除 App Sandbox**(自用,需任意文件夹读权限)。
3. File → Add Package Dependencies → Add Local → 选 `~/Mneme`(引入 `MnemeCore`);再 Add `https://github.com/sindresorhus/KeyboardShortcuts`(供 Task 15)。
4. 删除模板生成的 `ContentView.swift` 与默认 `MnemeApp.swift`(将由下方文件替换)。

- [ ] **Step 2: 写 SourcesStore**

`App/Sources/SourcesStore.swift`:
```swift
import Foundation
import MnemeCore

struct SourceConfig: Codable, Identifiable, Equatable {
    var id: String
    var kind: SourceKind
    var path: String
}

@MainActor
final class SourcesStore: ObservableObject {
    @Published private(set) var sources: [SourceConfig] = []
    private let key = "mneme.sources.v1"

    init() { load() }

    func add(kind: SourceKind, path: String) {
        guard !sources.contains(where: { $0.path == path && $0.kind == kind }) else { return }
        sources.append(SourceConfig(id: UUID().uuidString, kind: kind, path: path))
        save()
    }

    func remove(_ id: String) {
        sources.removeAll { $0.id == id }
        save()
    }

    func connectors() -> [SourceConnector] {
        sources.map { cfg in
            let url = URL(fileURLWithPath: cfg.path)
            switch cfg.kind {
            case .pdf:  return PDFConnector(root: url, sourceId: cfg.id)
            case .code: return CodeConnector(root: url, sourceId: cfg.id)
            default:    return NotesConnector(root: url, sourceId: cfg.id)
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SourceConfig].self, from: data) else { return }
        sources = decoded
    }
    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(sources), forKey: key)
    }
}
```

- [ ] **Step 3: 写 AppEnvironment(装配 + 配置不匹配自愈)**

`App/AppEnvironment.swift`:
```swift
import Foundation
import MnemeCore

@MainActor
final class AppEnvironment: ObservableObject {
    let embedder: EmbeddingService
    let store: IndexStore
    let query: QueryService
    let sources = SourcesStore()

    @Published var isIndexing = false
    @Published var lastStats: IndexRunStats?
    @Published var statusMessage = ""

    private init(embedder: EmbeddingService, store: IndexStore) {
        self.embedder = embedder
        self.store = store
        self.query = QueryService(embedder: embedder, store: store)
    }

    static func make() -> AppEnvironment {
        let embedder: EmbeddingService = (try? NLEmbeddingService())
            ?? HashingEmbeddingService(dimension: 256)
        let dir = appSupportDir()
        let dbPath = dir.appendingPathComponent("index.sqlite").path
        let store = openStore(path: dbPath, embedder: embedder)
        return AppEnvironment(embedder: embedder, store: store)
    }

    /// 打开索引;若嵌入器变更导致维度/标识不匹配,删库重建(原文与模型都在,可全量重建)。
    private static func openStore(path: String, embedder: EmbeddingService) -> IndexStore {
        do {
            return try IndexStore(path: path, embedderId: embedder.id, dimension: embedder.dimension)
        } catch {
            try? FileManager.default.removeItem(atPath: path)
            // swiftlint:disable:next force_try
            return try! IndexStore(path: path, embedderId: embedder.id, dimension: embedder.dimension)
        }
    }

    static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Mneme", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func reindex() async {
        guard !isIndexing else { return }
        isIndexing = true
        statusMessage = "索引中…"
        defer { isIndexing = false }
        do {
            let connectors = sources.connectors()
            let stats = try await IndexingPipeline(
                connectors: connectors, embedder: embedder, store: store
            ).run { [weak self] msg in
                Task { @MainActor in self?.statusMessage = msg }
            }
            lastStats = stats
            statusMessage = "完成:新增 \(stats.indexed)、跳过 \(stats.skipped)、失败 \(stats.failed)"
        } catch {
            statusMessage = "索引出错:\(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: 写 MnemeApp + 菜单栏内容**

`App/MnemeApp.swift`:
```swift
import SwiftUI

@main
struct MnemeApp: App {
    @StateObject private var env = AppEnvironment.make()

    var body: some Scene {
        MenuBarExtra("Mneme", systemImage: "brain") {
            MenuBarContent().environmentObject(env)
        }
        .menuBarExtraStyle(.window)

        Window("Mneme", id: "main") {
            MainWindow().environmentObject(env)
        }

        Settings {
            SettingsView().environmentObject(env)
        }
    }
}
```

`App/MenuBarContent.swift`:
```swift
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mneme").font(.headline)
            Text(env.statusMessage.isEmpty ? "就绪" : env.statusMessage)
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("打开主窗口") { openWindow(id: "main") }
            Button(env.isIndexing ? "索引中…" : "重建索引") {
                Task { await env.reindex() }
            }.disabled(env.isIndexing)
            Button("快搜(⌥Space)") {
                QuickSearchController.shared.toggle()   // Task 15 提供
            }
            Divider()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 240)
    }
}
```

> 说明:`MainWindow`(Task 14)、`SettingsView`(Task 16)、`QuickSearchController`(Task 15)此刻尚未定义,Step 5 先用空占位让其编译,后续任务替换。

- [ ] **Step 5: 临时占位(让项目可编译)**

`App/Placeholders.swift`(后续任务逐个删除对应占位):
```swift
import SwiftUI

struct MainWindow: View { var body: some View { Text("Search — Task 14") } }
struct SettingsView: View { var body: some View { Text("Settings — Task 16") } }

final class QuickSearchController {           // 占位,Task 15 替换
    static let shared = QuickSearchController()
    func toggle() {}
}
```

- [ ] **Step 6: 构建并冒烟**

Run: `xcodebuild -scheme Mneme -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`

手动冒烟:
1. 运行 app → 菜单栏出现 🧠 图标。
2. 点开 → 看到状态「就绪」、四个按钮。
3. 「打开主窗口」弹出窗口显示占位文字。
4. 「重建索引」此时无来源 → 状态显示「完成:新增 0、跳过 0、失败 0」。

- [ ] **Step 7: Commit**

```bash
git add App Mneme.xcodeproj
git commit -m "feat(app): scaffold menu-bar app, AppEnvironment, SourcesStore"
```

---

### Task 14: 搜索 UI(主窗口)

**Files:**
- Create: `App/Search/SearchViewModel.swift`
- Create: `App/Search/ResultRow.swift`
- Create: `App/Search/MainWindow.swift`
- Modify: `App/Placeholders.swift`(删除其中 `MainWindow` 占位)

- [ ] **Step 1: 写 SearchViewModel(带防抖)**

`App/Search/SearchViewModel.swift`:
```swift
import Foundation
import MnemeCore

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var queryText = ""
    @Published var hits: [SearchHit] = []
    @Published var isSearching = false

    private var query: QueryService?
    func attach(_ q: QueryService) { if query == nil { query = q } }

    /// 由 `.task(id: queryText)` 调用:换字时自动取消上一次,实现 150ms 防抖。
    func search(_ text: String) async {
        guard let query else { return }
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { hits = []; return }
        do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return } // 被取消即放弃
        isSearching = true
        defer { isSearching = false }
        let results = (try? await query.search(q, topK: 30)) ?? []
        if !Task.isCancelled { hits = results }
    }
}
```

- [ ] **Step 2: 写 ResultRow(主窗口与快搜共用)**

`App/Search/ResultRow.swift`:
```swift
import SwiftUI
import MnemeCore

struct ResultRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title ?? hit.uri.lastPathComponent).font(.headline).lineLimit(1)
                Text(hit.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(hit.uri.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.2f", hit.score)).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch hit.kind {
        case .notes: return "note.text"
        case .pdf: return "doc.richtext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .transcript: return "waveform"
        case .activity: return "calendar"
        }
    }
}
```

- [ ] **Step 3: 写 MainWindow,并删除占位**

`App/Search/MainWindow.swift`:
```swift
import SwiftUI
import AppKit
import MnemeCore

struct MainWindow: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索我的文件…", text: $vm.queryText).textFieldStyle(.plain)
                if vm.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(10)
            Divider()
            if vm.hits.isEmpty {
                ContentUnavailableView("无结果", systemImage: "magnifyingglass",
                                       description: Text("输入关键词,或先在「设置」里添加来源并重建索引。"))
                    .frame(maxHeight: .infinity)
            } else {
                List(vm.hits, id: \.chunkId) { hit in
                    ResultRow(hit: hit)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(hit.uri) }
                }
            }
        }
        .onAppear { vm.attach(env.query) }
        .task(id: vm.queryText) { await vm.search(vm.queryText) }
        .frame(minWidth: 640, minHeight: 440)
    }
}
```

在 `App/Placeholders.swift` 中删除 `struct MainWindow ...` 那一行占位(保留 `SettingsView` 与 `QuickSearchController` 占位)。

- [ ] **Step 4: 构建并冒烟**

Run: `xcodebuild -scheme Mneme -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`

手动冒烟(需先有可索引内容;若还没来源,Task 16 后再完整验证):
1. 打开主窗口 → 见搜索框 + 「无结果」空态。
2. 临时:在代码里 `sources.add(kind:.notes, path:"<某 vault>")` 或等 Task 16;重建索引后输入关键词 → 出现结果行(图标/标题/片段/分数)。
3. 双击结果 → 用默认 app 打开对应文件。

- [ ] **Step 5: Commit**

```bash
git add App/Search App/Placeholders.swift
git commit -m "feat(app): add semantic search main window with debounced query"
```

---

### Task 15: 全局热键 + QuickSearch 悬浮窗(NSPanel)

**Files:**
- Create: `App/QuickSearch/Shortcuts.swift`
- Create: `App/QuickSearch/QuickSearchView.swift`
- Create: `App/QuickSearch/QuickSearchController.swift`
- Modify: `App/Placeholders.swift`(删除 `QuickSearchController` 占位)
- Modify: `App/AppEnvironment.swift`(`make()` 末尾注册热键 + 配置控制器)

- [ ] **Step 1: 定义热键名**

`App/QuickSearch/Shortcuts.swift`:
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleQuickSearch = Self("toggleQuickSearch",
                                        default: .init(.space, modifiers: [.option]))
}
```

- [ ] **Step 2: 写 QuickSearchView**

`App/QuickSearch/QuickSearchView.swift`:
```swift
import SwiftUI
import AppKit
import MnemeCore

struct QuickSearchView: View {
    let query: QueryService
    let onClose: () -> Void

    @State private var text = ""
    @State private var hits: [SearchHit] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            TextField("问我的文件…", text: $text)
                .textFieldStyle(.plain).font(.title2).padding(14)
                .onChange(of: text) { _, newValue in schedule(newValue) }
            Divider()
            List(hits, id: \.chunkId) { hit in
                ResultRow(hit: hit)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { NSWorkspace.shared.open(hit.uri); onClose() }
            }
        }
        .frame(width: 640, height: 420)
        .onExitCommand { onClose() }   // Esc 关闭
    }

    private func schedule(_ q: String) {
        task?.cancel()
        task = Task {
            let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { hits = []; return }
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            if Task.isCancelled { return }
            hits = (try? await query.search(trimmed, topK: 20)) ?? []
        }
    }
}
```

- [ ] **Step 3: 写 QuickSearchController,并删除占位**

`App/QuickSearch/QuickSearchController.swift`:
```swift
import AppKit
import SwiftUI
import MnemeCore

@MainActor
final class QuickSearchController {
    static let shared = QuickSearchController()
    private var panel: NSPanel?
    private var query: QueryService?

    func configure(query: QueryService) { self.query = query }

    func toggle() {
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        guard let query else { return }
        let panel = self.panel ?? makePanel(query: query)
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel(query: QueryService) -> NSPanel {
        let root = QuickSearchView(query: query) { [weak self] in self?.panel?.orderOut(nil) }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: root)
        return panel
    }
}
```

在 `App/Placeholders.swift` 中删除 `QuickSearchController` 占位类(此时 `Placeholders.swift` 应只剩 `SettingsView` 占位)。

- [ ] **Step 4: 在 AppEnvironment.make() 末尾注册热键**

在 `App/AppEnvironment.swift` 顶部加 `import KeyboardShortcuts`;把 `make()` 改成在返回前注册:

```swift
    static func make() -> AppEnvironment {
        let embedder: EmbeddingService = (try? NLEmbeddingService())
            ?? HashingEmbeddingService(dimension: 256)
        let dir = appSupportDir()
        let dbPath = dir.appendingPathComponent("index.sqlite").path
        let store = openStore(path: dbPath, embedder: embedder)
        let env = AppEnvironment(embedder: embedder, store: store)

        QuickSearchController.shared.configure(query: env.query)
        KeyboardShortcuts.onKeyUp(for: .toggleQuickSearch) {
            QuickSearchController.shared.toggle()
        }
        return env
    }
```

- [ ] **Step 5: 构建并冒烟**

Run: `xcodebuild -scheme Mneme -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`

手动冒烟:
1. 运行 app,按 `⌥Space` → 屏幕中央弹出悬浮搜索框。
2. 输入关键词 → 实时出结果;`Esc` 关闭;再按 `⌥Space` 切换显隐。
3. 双击结果打开文件并自动关闭面板。

- [ ] **Step 6: Commit**

```bash
git add App/QuickSearch App/AppEnvironment.swift App/Placeholders.swift
git commit -m "feat(app): add global-hotkey Spotlight-style quick search panel"
```

---

### Task 16: 设置(来源管理 + 重建索引 + 登录项 + 热键)

**Files:**
- Create: `App/Settings/SettingsView.swift`
- Delete: `App/Placeholders.swift`(占位已全部被替换)

- [ ] **Step 1: 写 SettingsView,并删除占位文件**

`App/Settings/SettingsView.swift`:
```swift
import SwiftUI
import AppKit
import ServiceManagement
import KeyboardShortcuts
import MnemeCore

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    var body: some View { SettingsBody(env: env, sources: env.sources) }
}

private struct SettingsBody: View {
    let env: AppEnvironment
    @ObservedObject var sources: SourcesStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("来源文件夹") {
                if sources.sources.isEmpty {
                    Text("尚未添加来源").foregroundStyle(.secondary)
                }
                ForEach(sources.sources) { src in
                    HStack {
                        Text(src.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(src.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) { sources.remove(src.id) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("添加笔记夹") { addFolder(.notes) }
                    Button("添加论文夹") { addFolder(.pdf) }
                    Button("添加代码仓") { addFolder(.code) }
                }
            }

            Section("索引") {
                HStack {
                    Button(env.isIndexing ? "索引中…" : "重建索引") {
                        Task { await env.reindex() }
                    }.disabled(env.isIndexing)
                    Text(env.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("快捷键与启动") {
                KeyboardShortcuts.Recorder("快搜热键:", name: .toggleQuickSearch)
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }

    private func addFolder(_ kind: SourceKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let path = panel.url?.path {
            sources.add(kind: kind, path: path)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

删除 `App/Placeholders.swift`(其内容已被 Task 14/15/16 全部替换)。

- [ ] **Step 2: 构建**

Run: `xcodebuild -scheme Mneme -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 端到端手动冒烟(P1 验收)**

1. 运行 app → 菜单栏 🧠。
2. 打开「设置」→ 添加你的 Obsidian vault(笔记夹)+ 一个论文 PDF 夹。
3. 点「重建索引」→ 状态显示新增数量、无报错。
4. 改一个 `.md` 文件 → 再次「重建索引」→ 该文档「跳过」之外仅 1 个「新增」(增量生效)。
5. 按 `⌥Space` → 输入中文/英文关键词 → 命中相关笔记/PDF。
6. 双击结果 → 打开对应文件。
7. 设置里改热键、开关开机自启 → 行为符合预期。

- [ ] **Step 4: Commit**

```bash
git add App/Settings
git rm App/Placeholders.swift
git commit -m "feat(app): add settings (sources, reindex, login item, hotkey recorder)"
```

---

### Task 17: 升级到多语 CoreML e5(可选收尾,需离线模型准备)

> P1 已可用(NLEmbedding,英文为主)。本任务把默认嵌入器升级为 **multilingual-e5-small** 的 CoreML 版,获得真·中英跨语检索。这是本计划唯一需要离线模型准备的任务,验证为手动集成。索引会因 `embedder.id` 变化在下次启动时自动重建(见 `AppEnvironment.openStore`)。

**Files:**
- Create: `scripts/convert_e5_to_coreml.py`(离线转换,跑一次)
- Create: `App/CoreMLEmbeddingService.swift`(放 app target,依赖 swift-transformers)
- Modify: `App/AppEnvironment.swift`(优先用 CoreML,失败回退 NL)
- 在 Xcode 添加包依赖 `https://github.com/huggingface/swift-transformers`

- [ ] **Step 1: 离线转换模型(跑一次,产物入 app 资源)**

`scripts/convert_e5_to_coreml.py`(用 `uv` 跑;产出 `multilingual-e5-small.mlpackage` 与 `tokenizer.json`):
```python
# uv run --with sentence-transformers --with coremltools --with torch scripts/convert_e5_to_coreml.py
import coremltools as ct
import torch
from transformers import AutoModel, AutoTokenizer

MODEL = "intfloat/multilingual-e5-small"          # 384 维,多语
tok = AutoTokenizer.from_pretrained(MODEL)
model = AutoModel.from_pretrained(MODEL).eval()

class MeanPooled(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, input_ids, attention_mask):
        out = self.m(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
        mask = attention_mask.unsqueeze(-1).float()
        summed = (out * mask).sum(1)
        counts = mask.sum(1).clamp(min=1e-9)
        return summed / counts                     # mean pooling(e5 约定)

wrapped = MeanPooled(model).eval()
ids = torch.ones(1, 32, dtype=torch.int32)
mask = torch.ones(1, 32, dtype=torch.int32)
traced = torch.jit.trace(wrapped, (ids, mask))
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input_ids", shape=(1, ct.RangeDim(1, 512)), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, ct.RangeDim(1, 512)), dtype=int)],
    minimum_deployment_target=ct.target.macOS14,
    compute_units=ct.ComputeUnit.ALL,
)
mlmodel.save("multilingual-e5-small.mlpackage")
tok.save_pretrained("e5-tokenizer")               # 含 tokenizer.json
print("done")
```
把 `multilingual-e5-small.mlpackage` 与 `e5-tokenizer/tokenizer.json` 拖进 Xcode 的 Mneme target(勾选 Copy if needed、加入 target membership)。

> 备注:e5 用 XLM-R(sentencepiece)分词,swift-transformers 的 `AutoTokenizer` 可从 `tokenizer.json` 加载。若分词器加载有出入,以 `tokenizer.json` 为准微调。

- [ ] **Step 2: 写 CoreMLEmbeddingService**

`App/CoreMLEmbeddingService.swift`:
```swift
import Foundation
import CoreML
import Tokenizers          // swift-transformers
import MnemeCore

public struct CoreMLEmbeddingService: EmbeddingService {
    public let id = "coreml-e5-small-v1"
    public let dimension = 384
    private let model: MLModel
    private let tokenizer: Tokenizer
    private let maxLen = 256

    public init() throws {
        guard let modelURL = Bundle.main.url(forResource: "multilingual-e5-small",
                                             withExtension: "mlpackage"),
              let tokURL = Bundle.main.url(forResource: "tokenizer", withExtension: "json")
        else { throw EmbeddingError.modelUnavailable }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        self.model = try MLModel(contentsOf: MLModel.compileModel(at: modelURL), configuration: cfg)
        self.tokenizer = try await_loadTokenizer(tokURL)   // 见下方 helper
    }

    public func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        let prefix = (kind == .query) ? "query: " : "passage: "   // e5 前缀约定
        return try texts.map { try embedOne(prefix + $0) }
    }

    private func embedOne(_ text: String) throws -> [Float] {
        var ids = tokenizer.encode(text: text)
        if ids.count > maxLen { ids = Array(ids.prefix(maxLen)) }
        let n = ids.count
        let idArr = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32)
        let maskArr = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32)
        for i in 0..<n { idArr[i] = NSNumber(value: ids[i]); maskArr[i] = 1 }
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["input_ids": idArr, "attention_mask": maskArr])
        let out = try model.prediction(from: input)
        let name = out.featureNames.first { $0 != "input_ids" && $0 != "attention_mask" }!
        let vec = out.featureValue(for: name)!.multiArrayValue!
        var result = [Float](repeating: 0, count: dimension)
        for i in 0..<dimension { result[i] = vec[i].floatValue }
        return Vector.normalize(result)
    }
}
```

> 分词器加载:swift-transformers 的 `AutoTokenizer.from(...)` 为 async。在 `init` 里用同步包装或把服务构造改为 async 工厂 `static func make() async throws -> CoreMLEmbeddingService`,并在 `AppEnvironment.make()` 内 `await`。实现时择一,保持 `EmbeddingService` 协议不变。

- [ ] **Step 3: 在 AppEnvironment 优先用 CoreML**

把 `make()` 的嵌入器选择改为(失败回退 NL,再回退 Hashing):
```swift
let embedder: EmbeddingService =
    (try? CoreMLEmbeddingService())
    ?? (try? NLEmbeddingService())
    ?? HashingEmbeddingService(dimension: 256)
```

- [ ] **Step 4: 构建 + 手动集成验证**

Run: `xcodebuild -scheme Mneme -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`

手动验证(多语 + 质量):
1. 启动 → 因 `embedder.id` 变化,索引自动重建(状态可见)。
2. 用**中文 query** 搜**英文笔记**(及反向)→ 能跨语命中(NLEmbedding 做不到,这是升级目的)。
3. 用 `eval` 风格的几条 query 人工核对 top1 是否正确。
4. 菜单栏「就绪」、热键正常。

- [ ] **Step 5: Commit**

```bash
git add scripts/convert_e5_to_coreml.py App/CoreMLEmbeddingService.swift App/AppEnvironment.swift
git commit -m "feat(app): upgrade to multilingual e5 CoreML embeddings"
```

---

## 完成定义(P0+P1 Done)

- [ ] `swift test` 全绿(Tasks 1–12 的单元/集成/评测)。
- [ ] Xcode `Mneme` target 构建通过、可运行。
- [ ] 能添加笔记/PDF/代码来源并完成索引,增量刷新只处理变化文档。
- [ ] `⌥Space` 唤起悬浮窗,中英查询命中相关文档,双击跳原文。
- [ ] 评测 harness 在 fixture 上 Hit@5 ≥ 0.9、MRR ≥ 0.8。
- [ ] (Task 17 完成后)中↔英跨语检索可用。

## Spec 覆盖映射(对照 [模块① spec](../01-module-index-query.md))

| 模块① spec 要点 | 对应 Task |
|---|---|
| SourceConnector 协议 | Task 6 |
| NotesConnector / PDFConnector / CodeConnector | Task 6 / 7 / 8 |
| Chunker(滑窗 + overlap + locator) | Task 3 |
| EmbeddingService(query/passage 前缀、归一化) | Task 4 / 11 / 17 |
| IndexStore(增量 hash 去重、级联删除、检索) | Task 5 |
| IndexingPipeline(增量、韧性) | Task 9 |
| QueryService(检索 + 文档级去重) | Task 10 |
| RAG 问答(P2) | 不在本计划(后续 P2 计划) |
| QuickSearch 悬浮窗 UX(热键、列表、跳转) | Task 14 / 15 |
| 评测 Hit@k / MRR | Task 12 |
| 隐私:非沙箱、零运行时联网 | Task 13(非沙箱)+ 全程无网络调用 |

## 不在本计划(各自后续单独成计划)

- **P2** 模块①-RAG:MLX 本地 LLM、带引用问答、prompt 模板、上下文预算。
- **P3** 模块③ 活动日志:FSEvents/git → Obsidian 写回 → 汇入索引。
- **P4** 模块② 转写:WhisperKit → TranscriptConnector → 索引 + 导出。
- **优化项**:sqlite-vec KNN 替换暴力余弦;FSEvents 实时增量(本计划用手动「重建」触发);页/行级精确跳转。
