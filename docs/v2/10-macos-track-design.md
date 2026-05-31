# Mneme v2 — macOS 轨设计明细(v2.0 – v2.3)

- 状态:Implemented on `main` / 验证基线 107 XCTest
- 日期:2026-05-29;更新:2026-05-31
- 基于分支:`main`(merge commit `aea771c`,含 `develop` 的 `65157ea`)
- 上游:见主文档 [`00-roadmap.md`](00-roadmap.md)(跨平台契约 §3、共享模式 §4、锁定决策 §5)
- 性质:设计 + 落地对照文档。历史"现状核对"来自 `develop` 设计阶段;当前状态以 `main` 源码和验证命令为准。

> 统一前提(来自主文档,不再重复):对外 MCP/CLI/DTO 契约逐字一致;`answer` 默认 extractive;`IndexStore` 切 WAL;stdio MCP 为手写实现。

## 当前落地状态

- v2.0-v2.3 macOS 轨已落在 `main`:CLI/MCP、remember、agent session、FTS5/RRF、web clip、Zotero connector 均有源码与 XCTest 覆盖。
- 打包形态:`Contents/MacOS/Mneme` 是 GUI app,`Contents/Helpers/mneme` 是 headless helper,避免大小写不敏感文件系统上 `Mneme`/`mneme` 互相覆盖。
- 当前 repo fixture 是根目录 `eval/queries.jsonl`;`EvalTests` 会优先读它,缺失时才 fallback 到 bundle fixture。

---

## v2.0 — Agent 接口地基(MCP server + CLI)

### 目标
独立 `mneme` 二进制:`mneme mcp`(stdio,4 个 tool)+ `mneme search/answer/sources/remember/doctor` CLI,查询和写入受管记忆时复用 `QueryService`/`MemoryService`,全程零运行时联网。

### 现状核对(设计阶段已确认;当前已实现)
- **DB 路径**:`~/Library/Application Support/Mneme/index.sqlite`(`AppEnvironment.make`)。
- **并发**:`IndexStore` 是 `actor` + GRDB **`DatabaseQueue`**(单连接串行),当前已按 D1 切 WAL。
- **存储/检索**:向量存 BLOB,`search` 是**全表暴力点积**(纯 Swift,非 sqlite-vec)。
- **查询只需 embedder + store**:`QueryService.search` 仅用 `embedder.embed(.query)` + `store.search`;`answer` 额外需 `RagAnswerGenerator`(默认 `ExtractiveRagAnswerGenerator()`,纯本地无模型)。
- **装配**:`CoreMLE5EmbeddingService` / e5 资源定位 / fallback 已通过 `QueryServiceFactory` 下沉到 `MnemeCore` 可复用路径。
- **来源清单**:`SourcesStore` 仍存 `UserDefaults`(`mneme.sources.v1`),CLI/MCP 通过 `SourcesReader` 读取并结合索引计数。

### 核心架构抉择 → 推荐 A:独立二进制 + 只读打开 DB
| 维度 | (A) 独立二进制 | (B) 瘦客户端→GUI IPC |
|---|---|---|
| 可用性 | **GUI 不需运行**,headless/CI 可用 | 依赖 GUI 在跑 |
| 内存 | 每次调用独立进程(search 几十 MB / answer 载 MLX GB 级) | 复用 app 热模型,近 0 |
| DB 锁 | 配合 **WAL** 只读连接,读不阻塞 GUI 已提交数据 | 单进程独占,无冲突 |
| 复杂度 | 中(需下沉装配) | 高(要设计 IPC + app server) |

选 A:headless 可用是 agent 场景硬需求,`QueryService` 已是 `Sendable` 值类型可在新进程重建。MCP 走 stdio、CLI 进程内直调,**无任何 socket**,彻底规避联网灰区。B 方案(复用热 MLX)留作 v2.0 之后的性能优化。

### MCP 工具面
当前 MCP 暴露 4 个 tool(input/output 见主文档 §3),不暴露 resources(语料是动态查询结果,留后续):
- `mneme.search` → `QueryService.search`
- `mneme.answer` → `QueryService.answer`(**同步返回完整答案**;MCP 不原生流式,`answerStream` 不暴露;CLI/MCP 固定 `ExtractiveRagAnswerGenerator`,MLX 只在 macOS GUI 路径启用)
- `mneme.list_sources` → 读 `SourcesStore` 配置 + `IndexStore.documentCount`
- `mneme.remember` → 写受管 memory Markdown 并立即索引

`kinds`/`sourceIds` → `SearchFilter(kinds:sourceIds:)`。

### 代码落点
**下沉 MnemeCore(可测):**
- `Sources/MnemeCore/Composition/QueryServiceFactory.swift`:
  `makeReadOnly(appSupportDirectory:)` / `makeReadWrite(appSupportDirectory:)`(抽出 embedder 选择 e5→NLEmbedding→Hashing、只读 store 打开、remember 写回路径)。
- 迁入 MnemeCore:`CoreMLE5EmbeddingService` / `CoreMLE5Loader` / `NLEmbeddingService`(仅依赖 CoreML/Tokenizers,可移)。
- `IndexStore` 加只读 init:`init(readonlyPath:embedderId:dimension:) throws`(GRDB `Configuration.readonly = true`,跳过建表、改为校验 config 表)+ **切 WAL**(`prepareDatabase` 设 `journalMode = .wal`)。
- `Sources/MnemeCore/Agent/MnemeQueryResult.swift`:`Codable` DTO(`SearchHitDTO`/`AnswerDTO`/`SourceSummaryDTO`),MCP 与 CLI 共用序列化边界。
- `Sources/MnemeCore/Agent/MnemeQueryFacade.swift`:`search(...)->[SearchHitDTO]` / `answer(...)->AnswerDTO` / `sources()->[SourceSummaryDTO]`。MCP/CLI 都只调它。
- `Sources/MnemeCore/Agent/SourcesReader.swift`:下沉 `mneme.sources.v1` 的 decode 逻辑供 CLI/App 共用。

**新 executable product `mneme`**(`Package.swift` 中 product 为 `mneme`,target/module 为 `MnemeCLI`,避免与 GUI app target 在大小写不敏感文件系统上冲突):
- `CLI/main.swift`:子命令分发。
- `CLI/MCPServer.swift`:stdio JSON-RPC 循环,`initialize`/`tools/list`/`tools/call`,调 facade。**只做协议解析转发,无业务逻辑。**

### 安全 / 边界
- **写入边界**:`mneme search/answer/sources` 走只读 DB runtime;`mneme remember` 显式走 read-write runtime 写入受管 memory 并立即索引。
- **范围**:默认查全库;`--source`/`sourceIds` 收窄。**v2.0 不做 redaction**(数据是用户本地、不出本机),但 `doctor`/README 明示"任何能调此 MCP 的 agent 可读全部已索引内容"。
- **零联网**:CLI/MCP 固定 extractive,不加载 MLX,不自行下载模型;传入 `--mlx` 时显式报错而不是静默降级。
- **不静默吞错**:MCP 用 JSON-RPC error(db 缺失 / 维度不匹配 / 空查询);CLI 非零退出码 + stderr;新增 `MnemeAgentError`。

### 测试
XCTest(纳入当前 107 基线):`QueryServiceFactoryTests`(临时只读 DB + `HashingEmbeddingService`)、`MnemeQueryFacadeTests`(filter/DTO 映射)、`IndexStoreTests`(只读、FTS、metadata)、`MemoryServiceTests`、`AgentTranscriptConnectorTests`、`FtsQueryBuilderTests`、`RankFusionTests`、`WebClipConnectorTests`、`ZoteroConnectorTests`。
真实 smoke(沙箱外):`echo '{…initialize…}' | mneme mcp` 得 4 tool;`mneme search "…" --json` 对真实 DB 返回 hits;GUI 运行中并发 `mneme search` 无 `SQLITE_BUSY`(验 WAL)。

### 已定(见主文档 §9)
CLI 解析手写,不新增 ArgumentParser;CoreML/e5 路径下沉 `MnemeCore`;`list_sources` 通过 `SourcesReader` 读配置并结合已索引 `sourceId` 计数。

### 粗分期
- **P0-a** `IndexStore` 只读 init + 切 WAL + `IndexStoreReadOnlyTests`(纯 MnemeCore)。
- **P0-b** 迁 `CoreMLE5*`/`NLEmbedding` 入 MnemeCore + `QueryServiceFactory` + 测试;`AppEnvironment` 改调工厂,**跑 107 基线验回归**。
- **P1-a** DTO + facade + 测试。
- **P1-b** `mneme` target + `search/answer/sources/doctor` CLI(`--json`)+ build 脚本拷二进制 + search smoke。
- **P2-a** `mneme mcp` stdio server(4 tool)+ handshake smoke + `.mcp.json` 示例。**完成即达成里程碑。**

---

## v2.1 — 双向 agent 记忆(写回 + 索引 agent 会话)

### 目标
agent 通过 `mneme.remember` 把发现写入可索引的本地记忆库;把 Claude Code / Codex 会话作为新内容来源索引。

### 现状核对(已确认)
- `SourceConnector` 协议仅 4 成员:`sourceId`、`kind: SourceKind`、`enumerate() throws -> [SourceItem]`、`extract(_:) throws -> ExtractedDocument`(全同步、`Sendable`)。
- `ExtractedDocument(id, title:String?, text, contentHash, meta:[String:String])`;`SourceItem(id, uri:URL, modifiedAt:Date?)`;`Chunk(ordinal, text, locator:TextLocator)`;`TextLocator` 仅 `page/startChar/endChar/startLine/endLine`(无任意 JSON 槽)。
- `SourceKind` 当前 `notes/pdf/code/transcript/activity`——**需加 `.memory`/`.agentSession`**。
- 去重:`IndexingPipeline.run()` 比对 `store.documentHash(id:) == document.contentHash`;`ContentHash.of` = SHA256 前 8 字节。
- **孤儿清理(硬约束)**:`run()` 在每个 connector 末尾用 `documentIDs(sourceId:)` 减本轮 `enumerate()` 的 id 集合,差集 `deleteDocument`。**任何新 connector 必须能 enumerate 出全部当前 document id,否则误删。**
- 写回先例:`DailyNoteWriter.writeManagedBlock` 用 `<!-- mneme:activity:start/end -->` 标记幂等写回;Transcript 走"每条一 JSON 文件 + connector 枚举目录"。

### (A) 写回 → 推荐:受管 `.md` 文件夹(Markdown-as-store)
- 否决"直接写 DB"(破单一索引入口、用户不可见)、否决"塞进 Notes 目录"(污染)。
- 记忆落 `~/Library/Application Support/Mneme/Memory/`,**一条一文件** `mem-<key>.md`(YAML frontmatter:`type/tags/source_ref/link/created/agent` + 正文)。复用"文件落盘→connector 枚举→pipeline 索引",零核心改动,用户可在 Obsidian 看/删,删文件即从索引消失(契合孤儿清理)。
- `mneme.remember` 输入:`text`(必填)、`tags`、`sourceRef`、`link`、`title`。
- **去重**:稳定 key = `ContentHash.of(normalize(text) + "|" + (sourceRef ?? ""))` 作文件名与 doc id;相同文本+归属 → 命中同文件 → pipeline `documentHash==contentHash` 直接 skip。`MemoryStore.write` 落盘前查重 no-op,避免 FSEvents 风暴。可加每日写入配额兜底。
- **即时索引**:抽 `IndexingPipeline.indexOne(document:sourceId:kind:uri:) async throws -> Bool`(`chunk → embed(.passage) → upsert`),`run()` 内循环改调它;`remember` 写后立即调 `indexOne`。后台周期 `run()` 做对账。

### (B) agent 会话索引 → `AgentTranscriptConnector`,`kind = .agentSession`
- **真实路径(已确认)**:Claude Code `~/.claude/projects/<slug>/<sessionUUID>.jsonl`(子 agent 在 `subagents/…`);Codex `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`(首行 `session_meta`)。
- **枚举**:接受 roots,递归找 `.jsonl`;每文件 = 一个 `SourceItem`(id = url,`modifiedAt` = mtime)。**默认只索引顶层会话、跳过 `subagents/`**(量极大),作为可开关项。
- **抽取**:解析 jsonl 只保留对话回合(Claude `type ∈ {user,assistant}` 且非 meta/非 local-command;Codex `response_item.payload.type=="message"` 且 `role ∈ {user,assistant}`),渲染成 `"[role] text\n"` join,**复用现有字符级 Chunker**。
- **id/hash**:doc id = 文件 url(满足孤儿清理);`contentHash = ContentHash.of(渲染文本)`(进行中会话 hash 会变 → 重嵌,可用 mtime 去抖)。
- **locator**:`TextLocator` 无"第几条消息"槽。先用 `startChar/endChar` 跳回渲染文本偏移(推荐);可选给 `TextLocator` 加 `messageIndex: Int?`(向后兼容增强)。
- **meta**:`agent`(claude-code/codex)、`project`、`session_id`、`git_branch`、`started_at`、`cli_version`;title = `"<agent> · <project> · <date>"`。

### 集成点
- `mneme.remember` 挂 v2.0 工具面:MnemeCore 暴露纯逻辑 `MemoryService`(注入 `MemoryStore` + `IndexingPipeline.indexOne`),v2.0 MCP handler 只做"解析 args → 调 `MemoryService.remember(_:) async throws -> MemoryWriteResult` → 返回"。挂接面 = async 函数 + Codable I/O。
- 新 connector 注册:App 组装 `IndexingPipeline(connectors:[…])` 时追加 `MemoryConnector` 与 `AgentTranscriptConnector`;`QueryService`/`IndexStore` 零改动。

### 代码落点
- `Model/Types.swift`:`SourceKind` 加 `.memory` / `.agentSession`。
- `Sources/MnemeCore/Memory/`:`MemoryRecord.swift`(Codable + frontmatter 渲染/解析)、`MemoryStore.swift`(`write/list/delete/stableKey`)、`MemoryService.swift`(`remember`)。
- `Sources/MnemeCore/Connectors/MemoryConnector.swift`、`AgentTranscriptConnector.swift` + `Connectors/AgentLog/`(`ClaudeSessionParser.swift`/`CodexRolloutParser.swift`/`AgentTurn.swift`,拆小文件)。
- `Pipeline/IndexingPipeline.swift`:抽 `indexOne(...)`。
- App:`App/Memory/` 浏览/删除 UI;Sources 设置加 agent 日志目录 + `subagents` 开关。

### 测试 / 风险 / 分期
- 测试:`MemoryStoreTests`(同 `(text,sourceRef)` 写两次→一文件、skip)、`MemoryServiceTests`(`SpyEmbeddingService` + 内存 store 断言 `kind==.memory` 命中)、`AgentTranscriptConnectorTests`(Claude/Codex fixture 各一,只抽对话、跳 hook/meta、id 稳定、meta 含 project/session)、`IndexingPipelineTests` 扩孤儿清理。预计 +8~12 XCTest。
- 风险:`subagents/**` 范围(默认跳过)、进行中会话去抖、记忆库位置(App Support vs Obsidian vault)、**会话日志含 secrets → redaction(见主文档 §7)**、jsonl schema 漂移(防御式解析,坏行跳过)。
- 分期:**v2.1a 写回(先)** → **v2.1b 会话索引(后)**(格式调研更重、含隐私)。

---

## v2.2 — 检索质量(混合检索 + 重排 + eval 守门)

### 目标
不破坏现有纯向量检索,加 FTS5(BM25)关键词召回 + RRF 融合 + 可选本地重排,扩 eval 守住不回归。

### 现状核对(已确认,关键)
- **存储 = BLOB,检索 = 全表暴力点积**(纯 Swift `Vector.dot`,非 vDSP,非 sqlite-vec,无 FTS)。`search` 拉全部 chunk 逐行点积、内存排序 `prefix(topK)`,向量已 L2 归一化(点积≈cosine)。
- schema:`config(key,value)` / `documents` / `chunks(id,document_id,ordinal,text,locator_json)` / `chunk_vec(chunk_id, embedding BLOB)`;`chunk_id = "<docId>#<ordinal>"`。
- **版本/迁移**:无 `schema_version`、无 GRDB migrator;唯一绑定是 `config` 的 `embedder_id`+`dimension`,不匹配抛 `dimensionMismatch` → App `quarantineIncompatibleIndex` 改名 `*.incompatible-<ts>` 重建。**`createSchema` 全用 `CREATE TABLE IF NOT EXISTS`,新增表对旧库无害。**
- `QueryService.search`:embed → `store.search(topK*4)` → `collapseByDocument`(按 documentId 取最高分)→ `prefix(topK)`;放大系数 `*4` 写死(应提为常量 `rankInflation`)。
- Eval(`Eval/RetrievalEval.swift`):纯函数 `hitAtK`/`reciprocalRank`/`aggregate`;查询 fixture 存在于根目录 `eval/queries.jsonl`(门槛 Hit@5≥0.9、MRR≥0.8)。
- GRDB 6.29.3 自带 FTS5。

### 混合检索方案
- **关键词侧**:`IndexStore` 加 standalone FTS5 虚表 `chunk_fts(chunk_id UNINDEXED, text)`,由 `IndexStore.upsert/deleteChunks/backfillFTSIfNeeded` 同步,新增 `searchLexical(query, topK, filter) -> [SearchHit]`(`bm25(chunk_fts)` 排序,过滤复用现有 JOIN)。
- **中英日韩分词**:FTS5 `unicode61` 不切 CJK/Hangul → 对 query 做 **bigram 预处理**(`FtsQueryBuilder.build(_:) -> String`,纯函数:连续 CJK、平/片假名、谚文切 2-gram 用 OR 拼,英文按 token)。务实取舍,不依赖未编译进 SQLite 的 ICU。
- **融合 = RRF**(推荐,对量纲不敏感):`score = Σ 1/(k + rank_i)`,默认 `k=60`。在 `QueryService` 层融合两路 chunk 排名(不进 IndexStore)。
- **协同**:两路各取 `topK*4` → chunk 粒度 RRF → 再 `collapseByDocument` → `prefix(topK)`(先 RRF 后 collapse)。

### 重排方案
- **第一步不引模型**:RRF 已是隐式重排;加可选纯 lexical 精排 `LexicalReranker`(query term 覆盖率 / 标题命中),零成本可单测。
- **第二步(可选)**:CoreML cross-encoder(`ms-marco-MiniLM-L-6-v2` 量级)只对 RRF top~20 打分,延迟约每候选 1-3ms ANE、内存 ~90MB;作可插拔 `protocol Reranker` 实现,**默认关闭**,模型走与 e5 同级的"首次本地准备一次"路径(不新增网络)。

### schema 迁移(经核实:无损)
- FTS5 虚表走 `createSchema` 追加 `CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(chunk_id UNINDEXED, text, tokenize='unicode61')`。同步只通过 `IndexStore` 写路径完成,不依赖 SQLite trigger,因为索引文本要先经过 Swift bigram 扩展。旧库新增表,`embedder_id`/`dimension` 不变 → **不触发 `*.incompatible` 重建**。
- 旧数据回填:构造时检测 FTS 行数为 0 而 chunks 非空 → 逐条读取 `chunks` 并用 `FtsQueryBuilder.indexText` 回填,无需用户重建。
- `config` 可加 `fts_version`(仅供未来 FTS schema 变更,不参与现有兼容门)。

### 接口变更(向后兼容)
- `func search(_ text:String, topK:Int=20, mode:SearchMode = .hybrid, filter:SearchFilter?=nil)`;`enum SearchMode { case vector, hybrid }`。
- `IndexStore.searchLexical(...)` 新增,现有 `search` 签名不动;`SearchHit` 新增 `meta` 用于本地 opener/source URL,融合分写入现有 `score`。
- `answer/answerStream` 透传 `mode`,默认 hybrid。

### 代码落点 / eval / 测试 / 分期
- 落点:`Index/IndexStore.swift`(FTS+回填+`searchLexical`)、`Query/Fusion.swift`(`RankFusion.rrf`)、`Query/FtsQueryBuilder.swift`、`Query/SearchMode.swift`、`Query/QueryService.swift`(融合编排)、`RAG/Reranker.swift`(第二步)。
- eval:`eval/queries.jsonl` 作为 repo fixture,每行 `{query, expected}`;`EvalTests.test_hybridEvalNotWorseThanVector` 跑 vector vs hybrid,断言 `hybrid ≥ vector`。验证混合优于纯向量:构造"关键词强语义弱"子集(精确术语/代码标识符/罕见专名)分子集报告。
- 测试:`FtsQueryBuilderTests`(切词+转义防注入)、`RankFusionTests`、`IndexStoreTests`(searchLexical/旧库回填/metadata 持久化)、`QueryServiceTests`(vector vs hybrid)、`EvalTests`。真实 smoke:用旧版真实 DB 验无损升级 + FTS 命中。
- 分期:**Phase A FTS5+RRF(无模型)**+ eval 守门 → **Phase B 重排器**(先 LexicalReranker 再评估 CrossEncoder)。
- 已定(主文档 §9):默认 hybrid;本期不引重排模型。
- 范围守界:**不改向量侧**(sqlite-vec 属另一里程碑);暴力点积 O(N) 全表扫保留。

---

## v2.3 — 新来源(Zotero + 网页剪藏)

### 目标
新增两个 `SourceConnector`,严格复用 `enumerate→extract→contentHash→稳定 id→meta`,**不动核心查询路径**。

### 现状核对(已确认)
- 协议见 v2.1;现有 connector 套路:`FileManager.enumerator` 按扩展名过滤 → `id = url.absoluteString`、`uri = url` → `extract` 读内容 → `contentHash = ContentHash.of(body)` → 来源元数据进 `meta`(如 `pages/language/wikilinks`)→ `enumerate` 末尾按 id 排序。
- **`upsert` 写入 `item.uri`,不是 document 的 uri**(Zotero/web 设计需对齐)。
- App 注册:`SourceConfig{id,kind,path,bookmarkData}` 存 `UserDefaults`;`SourcesStore.connectors()` 内 `switch config.kind` 实例化 + `startAccessingSecurityScopedResource()`;`SettingsView` 现仅 3 按钮(notes/pdf/code,`NSOpenPanel`)。`SourceKind` 是 `String` + `CaseIterable`。

### (C1) Zotero → 推荐:只读复制 `zotero.sqlite` + 直读 `storage/` PDF
- 方案对比:(a) 直读 `zotero.sqlite`(元数据最全,但运行时锁库、schema 跨版本变);(b) 读 Better BibTeX 导出(稳定但要用户装插件);(c) 只扫 `storage/` PDF(丢元数据)。
- **推荐 (a) 的健壮变体**:`enumerate` 时 `FileManager.copyItem` 把 `zotero.sqlite` 复制到 `~/Library/Application Support/Mneme/zotero-cache/` 再 GRDB **只读**打开(绕开锁),防御式 SQL(单条目失败计入 Pipeline `failed`,不崩全局)。
- 抽取:每 item = 一个 Zotero 顶层条目;元数据 join `items/itemData/itemDataValues/fields/creators/itemTypes`(标题/作者/年份/abstractNote)、tags(`itemTags/tags`)、collection;关联 PDF 经 `itemAttachments.path`(`storage:<key>/<file>` → `~/Zotero/storage/<key>/`),**复用 `PDFTextExtractor`**(从 `PDFConnector` 抽出 PDF→文本+OCR 静态函数共用)。`text = 标题\n作者 年份\n摘要\n\n<PDF 全文>`。
- id:`"zotero://item/<itemKey>"`;`contentHash = ContentHash.of(metaBlock + pdfText)`;meta:`item_type/authors/year/tags/collections/attachment_path/zotero_key`。

### (C2) 网页剪藏 → 推荐:监听"剪藏文件夹"
- 方案对比:(a) 监听目录里用户保存的 `.html`/`.htm`/`.md`/`.markdown`/`.txt`(**最本地、用户显式触发、复用现有 `SourceFolderWatcher`**);(b) Services/Share Extension(需独立 target,非 sandbox 下注册不稳);(c) 内建 clipper(最接近后台联网红线)。**推荐 (a)**,(b) 留 v2.4+。`.webarchive` 暂不列入支持集,避免把二进制 plist 当 UTF-8。
- 正文抽取(纯本地):HTML 走纯 Swift 正则剥 `<script>/<style>/<nav>/<header>/<footer>/tag`;Markdown/TXT 按 plain text 保存,避免误删 `<`/`>` 比较符。`source_url` 从 `<meta property/name=og:url|canonical content=...>` 或 `<link rel=canonical href=...>` 抽取,属性顺序不敏感。
- **取舍**:本期不引 `WKWebView`/Readability,避免同步 `extract` 与 MainActor 摩擦,并避免本地 HTML 加载时触发远程资源请求的隐私风险。
- id = `url.absoluteString`;meta:`source_url`(优先 `<link rel=canonical>`/`og:url`,是"点回原网页"关键)、`clipped_at/byline/site_name`;`contentHash = ContentHash.of(正文)`。

### 代码落点 / 集成 / 测试 / 分期
- 落点:`Sources/MnemeCore/Connectors/ZoteroConnector.swift`、`WebClipConnector.swift`;抽 `Connectors/PDFTextExtractor.swift`(PDF 与 Zotero 共用,避免 DRY 违规)。App:`SettingsView` 加 `addFolder(.web)` + `addZoteroLibrary()`;`SourcesStore.connectors()` 加两 case。
- 集成:`SourceKind` 加 `.zotero`/`.web`(`String` raw `"zotero"`/`"web"`,`CaseIterable` → UI/filter 自动覆盖);Pipeline 零改动。**注意展示层**:web 的 `item.uri` 是本地文件,点击要跳原网页 → `ResultOpener` 读 `meta.source_url`(查询路径外的小改)。
- 接口签名:
  ```swift
  public struct ZoteroConnector: SourceConnector {
      public let kind: SourceKind = .zotero
      public init(libraryRoot: URL, sourceId: String, cacheDir: URL)
  }
  public struct WebClipConnector: SourceConnector {
      public let kind: SourceKind = .web
      public init(root: URL, sourceId: String)
  }
  ```
- 测试:`ZoteroConnectorTests`(手造迷你 `zotero.sqlite` + 1 页 PDF fixture,断言条目数/title/authors/year/tags/meta/PDF 片段/contentHash 稳定/PDF 缺失仅索引元数据不抛全局)、`WebClipConnectorTests`(`.html` fixture 含 `<article>`+广告 div+og:url,断言剥脚本/`source_url`/正文不变 hash 不变/WebView 不可用走正则降级)。
- 分期:**先 C2 网页剪藏**(更易、复用 watcher、有正则降级兜底)→ **后 C1 Zotero**(价值高更重,需真实库 smoke)。两者解耦可并行;共用前置:抽 `PDFTextExtractor`、`SourceKind` 加 2 case。
- 已定:macOS 走只读复制 `zotero.sqlite`;网页支持 `.html`/`.htm`/`.md`/`.markdown`/`.txt`,跳过 `.webarchive`;本期不走 WKWebView。`zotero://` 点击行为仍可后续增强。

---

> 实现顺序与跨里程碑共享项(`SourceKind` 扩展、`IndexingPipeline.indexOne` 抽取、core 下沉、`PDFTextExtractor`)见主文档 [§4](00-roadmap.md) / [§6](00-roadmap.md)。
