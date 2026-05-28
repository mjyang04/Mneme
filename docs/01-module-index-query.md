# 模块① — Index & Query(地基)

- 状态:Design / 待评审
- 依赖:无(其余模块依赖本模块)
- 对应建造期:P1(搜索)+ P2(RAG)

把笔记 / 论文 PDF / 代码统一建索引,提供语义搜索;phase2 加本地 LLM 做带引用的 RAG 问答。

---

## 1. 范围

**包含**
- 三个内容连接器:`NotesConnector`、`PDFConnector`、`CodeConnector`
- 分块 `Chunker`
- `EmbeddingService`(CoreML)
- `IndexStore`(向量增删查)
- `IndexingPipeline`(增量索引编排)
- `QueryService`(语义检索;P2 加 RAG)
- QuickSearch 悬浮窗 UX

**不包含**
- 语音转写(模块②)、活动捕获(模块③)——它们各自实现 `SourceConnector`,复用本模块的 Chunker/Embedding/Index/Query。

---

## 2. SourceConnector 协议

```swift
protocol SourceConnector {
    var sourceId: String { get }
    var kind: SourceKind { get }                 // .notes / .pdf / .code / ...

    /// 枚举当前来源下所有条目(增量:可只回变化项)
    func enumerate() async throws -> [SourceItem]

    /// 抽取某条目的纯文本 + 元数据 + 内容指纹
    func extract(_ item: SourceItem) async throws -> ExtractedDocument
}

struct SourceItem {
    let id: String          // 稳定 id(如 file:// 路径)
    let uri: URL
    let modifiedAt: Date?
}

struct ExtractedDocument {
    let id: String
    let title: String?
    let text: String
    let contentHash: String          // sha256(text) 前 16 hex
    let meta: [String: String]       // frontmatter / 语言 / 页数…
    let locators: [TextLocator]?     // 可选:文本各段 → 原文定位
}
```

---

## 3. 三个连接器

### 3.1 NotesConnector(Obsidian .md)
- 枚举 vault 下 `**/*.md`(忽略 `.obsidian/`、`.trash/`)。
- 解析 YAML frontmatter → `meta`(tags、aliases、自定义字段)。
- 正文剥离 frontmatter;保留标题层级用于 markdown 感知分块。
- wikilink `[[X]]` 抽出存入 meta(供日后做「链接邻居」加权,本版仅存)。
- 打开方式:`obsidian://open?vault=...&file=...` URI,点击结果直接跳 Obsidian。

### 3.2 PDFConnector(论文)
- 枚举来源文件夹 `**/*.pdf`。
- PDFKit `PDFDocument` 逐页 `page.string` 抽文本,记录页码到 `locators`。
- 某页文本为空(扫描件)→ 渲染该页为图 → Vision `VNRecognizeTextRequest`(支持中英)OCR 兜底。
- title 优先取 PDF 元数据 title,缺失则取文件名 / 首页大字号行。
- 打开方式:`file://` 打开 + 记录页码(理想态:跳到页;v1 至少打开文件)。

### 3.3 CodeConnector(代码)
- 枚举来源仓库的源码文件;**忽略** `.git/`、`node_modules/`、`build/`、`*.lock`、二进制、`outputs/`、`qdrant_storage/` 等。
- 用 `.gitignore` 风格的 ignore 列表(可配置)。
- 语言识别取扩展名;chunk 偏向「按空行/函数边界的近似块 + 固定上限」,locator 记行号区间。
- 打开方式:`file://`(理想态带行号,如交给编辑器 `xed -l` / VS Code URI)。

---

## 4. Chunker

- 默认策略:**markdown/文本感知滑窗**——优先在标题、段落、空行处断;目标块长约 `512 tokens`(用字符近似,中文按字数折算),`overlap ≈ 64`。
- 代码:按空行/缩进块聚合到上限,尽量不腰斩函数。
- 每个 chunk 保留 `ordinal` 与 `locator`(行号 / 页码 / 偏移),保证可跳回原文。
- 纯函数、无副作用,便于单测。

---

## 5. EmbeddingService(CoreML)

```swift
protocol EmbeddingService {
    var dimension: Int { get }                       // 384 (e5-small)
    func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]]
}
enum EmbedKind { case query, passage }               // e5 前缀约定
```

- 模型:`multilingual-e5-small` 转 CoreML;走 ANE。
- e5 约定:passage 加 `passage: ` 前缀,query 加 `query: ` 前缀(显著影响检索质量)。
- 批处理 + 限流;输出 L2 归一化向量(便于用内积≈余弦)。
- 降级:模型不可用时退 `NLEmbedding.sentenceEmbedding(for:)`(维度不同 → 触发整库重嵌或独立降级索引;本版选择「告警 + 暂停索引」,不混维)。

---

## 6. IndexStore(actor)

```swift
actor IndexStore {
    func upsert(document: ExtractedDocument,
                chunks: [Chunk], vectors: [[Float]]) async throws
    func deleteDocument(id: String) async throws
    func search(_ queryVector: [Float], topK: Int,
                filter: SearchFilter?) async throws -> [SearchHit]
    func documentHash(id: String) async throws -> String?   // 增量去重用
}

struct SearchHit {
    let chunkId: String
    let documentId: String
    let score: Float
    let text: String
    let title: String?
    let uri: URL
    let kind: SourceKind
    let locator: TextLocator?
}
```

- 向量检索:`sqlite-vec` 的 `vec0` 虚表 KNN;来源/类型过滤走普通列。
- v1 兜底:若不引 sqlite-vec,则把向量存 BLOB,用 `vDSP` 暴力内积 topK(数十万 chunk 仍毫秒级)。
- 增量:`upsert` 前比对 `content_hash`,未变跳过,变了先 `deleteDocument` 再写。
- 级联删除:删 document 自动删其 chunks 与向量。

---

## 7. IndexingPipeline

编排:`enumerate → (按 hash 过滤未变项) → extract → chunk → embed(batch) → IndexStore.upsert`。

- 触发:① 手动「重建/刷新」;② 来源文件夹 FSEvents 去抖后增量;③ 启动时轻量校对。
- 进度:暴露 `@Published` 进度(已处理/总数、当前文件、问题计数)给 UI。
- 韧性:逐文档 try/catch,单文档失败计入问题列表、不中断整体;基于 hash 可断点续跑。

---

## 8. QueryService

### P1:语义搜索
```swift
func search(_ text: String, topK: Int = 20,
            filter: SearchFilter? = nil) async throws -> [SearchHit]
```
1. `embed([text], kind: .query)` → 查询向量;
2. `IndexStore.search`;
3. 按 `documentId` 适度去重(同文档多 chunk 命中只折叠展示,可展开);
4. 返回带 `score` 的结果,UI 按相关度排序,显示来源类型 icon + 标题 + 命中片段高亮。

### P2:RAG 问答
```swift
func answer(_ question: String,
            topK: Int = 8) async throws -> RagAnswer   // 流式回调

struct RagAnswer {
    let text: String                 // 生成的答案(流式增量)
    let citations: [SearchHit]       // 引用的来源片段,可点击跳原文
}
```
- 检索 topK 片段 → 拼进固定模板 prompt → MLX LLM 流式生成。
- **强制引用**:prompt 要求答案中用 `[1][2]` 标注,`citations` 与序号一一对应,点击跳回原文。
- 上下文预算:按模型 ctx 截断,超出则降 topK 或截断片段。
- prompt 模板(草案):
  ```
  你是本地研究助手。仅依据【资料】回答;资料不足就说不知道。
  用简洁中文/英文(随问题语言)回答,并在引用处标注 [n]。
  【资料】
  [1] {title}\n{chunk}
  [2] ...
  【问题】{question}
  ```

---

## 9. QuickSearch 悬浮窗 UX

- 全局热键(默认 `⌥Space`,可改)→ `NSPanel`(borderless、nonactivating、屏幕居中)。
- 顶部单行输入框;下方结果列表(键盘 ↑↓ 选择,↩ 打开,⌘↩ 在 Finder/Obsidian 显示)。
- 模式切换:`搜索`(默认)/ `问`(P2,前缀 `?` 或快捷键切到 RAG)。
- 结果项:来源类型 icon · 标题 · 命中片段(query 词高亮)· 来源路径。
- `Esc` 收起;失焦自动隐藏;响应要快(输入防抖 ~150ms)。

---

## 10. 验收标准

- [ ] 能添加 vault / 论文夹 / 代码仓为来源并完成首次索引,进度可见。
- [ ] 改一个 md 文件后,增量索引在去抖窗口内自动更新该文档(不整库重建)。
- [ ] 中文 query 能命中英文笔记、反之亦然(多语 embedding 生效)。
- [ ] 热键唤起到出结果 < 300ms(库已建好、模型已驻留)。
- [ ] 点击结果能跳回原文(md→Obsidian,pdf/code→打开文件)。
- [ ] `eval` 集 Hit@5 ≥ 0.9、MRR ≥ 0.85(fixture 语料)。
- [ ]（P2)RAG 答案带可点击引用,引用确实来自检索片段。

---

## 11. 风险

- PDF 解析质量参差(双栏/公式/表格)→ 先保证文本型 PDF,扫描件 OCR 兜底,公式不强求。
- e5 前缀若用错会明显掉点 → 在 EmbeddingService 内强制加前缀,单测覆盖。
- 大代码仓首次索引耗时 → 默认排除常见噪声目录 + 后台低优先级 + 进度可见。
