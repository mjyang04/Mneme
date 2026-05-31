# Mneme v2 — Windows 轨设计明细(W2.0 – W2.3)

- 状态:Future design / 当前 `main` 保留 Windows Desktop, W2.x 尚未实现
- 日期:2026-05-29;更新:2026-05-31
- 基于分支:`main` 的 `Windows/`(Electron + Node,运行时**只用 Node 标准库**)
- 上游:见主文档 [`00-roadmap.md`](00-roadmap.md)(跨平台契约 §3、共享模式 §4、锁定决策 §5)
- 性质:设计 + 后续实现对照文档。所有"现状核对"基于 `Windows/mneme-windows.mjs` 等;W2.0-W2.3 仍是后续工作,不是当前已落地能力。

> 统一前提:未来 Windows MCP/CLI/DTO 契约应与 macOS **逐字一致**(主文档 §3);当前 Windows Desktop 仍强调**运行时零第三方依赖**(实测 `package.json` 无 `dependencies`,只有 devDeps electron/electron-builder)。

## 当前落地状态

- 当前 `main` 已保留 Windows Desktop app、local backend、tray/window shell、global shortcut、folder picker、installer workflow/files、`npm run windows:check` 和 `npm run windows:test`。
- 当前 Windows 尚未实现 W2.0 MCP/CLI、W2.1 memory/agent logs、W2.2 BM25+CJK、W2.3 Zotero/webclip;这些仍按本文排期。

---

## 共性认知:Windows 与 macOS 的结构差异(必须诚实呈现)

- Windows 是**纯词法检索 + 抽取式 Ask**,**无向量、无语义召回**。即便 W2.2 做满 BM25+CJK,"换个说法问同一件事"仍会漏——这是 macOS(BM25+向量混排+CoreML 重排)结构性领先处。
- **整合要求**:`windowsCapabilities()`(`mneme-windows.mjs:863-875`)与 README/roadmap 用诚实措辞:`"Local BM25 lexical search (no semantic vectors); search/answer quality is below the macOS hybrid build"`,不制造平价错觉。

---

## W2.0 — Node MCP server + CLI 地基

### 目标
为 Windows 版补齐 headless 对外接口:stdio MCP server + `mneme` CLI,工具面/CLI 与 macOS 逐字一致,只用 Node 标准库、零联网(stdio + loopback),不引向量/MLX/Whisper。

### 现状核对(已确认,行号可核)
- **HTTP 路由表**(`:303-366`,全部 `127.0.0.1`,CORS 仅 `http://127.0.0.1`):`GET /api/status`、`POST /api/sources`、`DELETE /api/sources/:id`、`POST /api/index/rebuild`、`GET /api/search?q=&kind=`、`GET /api/answer?q=`、`GET /api/transcripts`、`POST /api/transcripts/import-text`、`GET /api/activity`、`POST /api/settings`、`GET *`(静态)。
- **核心函数**:
  - `searchIndex(index, query, filters={kind})` → `[{id,documentId,kind,title,path,locator,score,snippet}]`(`:533-580`,**TF×IDF + 子串加权 8/4,固定 `.slice(0,20)`,无 topK 参数**)。
  - `answerFromIndex(index, query)` → `{answer, citations:[{number,title,path,locator,kind}]}`(`:582-615`,取 top **hardcoded 5**,citation 不含 score/snippet/uri)。
  - `rebuildIndex(dataDir)` → `stats{filesSeen,filesIndexed,documents,skipped,warnings}`(`:387-462`)。
- **存储**:`resolveDataDir`(`:128-146`),Windows = `%APPDATA%\Mneme`;Electron 覆盖为 `app.getPath("userData")`(`main.cjs:42`)。平铺 JSON:`sources.json/transcripts.json/index.json/settings.json`,原子写(temp+rename,`:894-904`)。
- **关键结构问题**:核心逻辑全部绑死在 `createWindowsDesktopBackend` 闭包的 `routes` 对象里(`:157-266`),`searchIndex/answerFromIndex/rebuildIndex` 是模块级私有、未 export。当前仅 export `resolveDataDir/createWindowsPreviewApp/createWindowsDesktopBackend`。
- **deps 核对**:`package.json` **无 `dependencies` 字段**,import 全是 `node:*`。→ "运行时零第三方依赖"属实。
- Electron 内 server 是 `port:0` 随机分配(`main.cjs:45`)→ 无法稳定连固定端口,佐证"独立进程"是对的。

### 架构抉择 → 推荐 A:独立 Node 进程复用 core
- (A) `node cli/mneme.mjs` 直读同一 `dataDir` JSON、跑同一 `searchCore/answerCore`:headless 不依赖 Electron、内存最小(无 Chromium)、任意 MCP host 可拉起。两个 reader 都只读 `index.json`,无写冲突。
- (B) 瘦客户端连 47732:端口随机 + 需 app 先跑,headless 不可用 → 否决。
- (C) 混合(CLI `--http <url>` 可选):YAGNI,本期不做。

### MCP 实现抉择 → 推荐手写 stdio JSON-RPC(标准库)
- 官方 `@modelcontextprotocol/sdk`:**违反"只用标准库"**,新增运行时 npm 依赖 + 打包要带 `node_modules`。
- 手写:stdio 上换行分隔 JSON-RPC 2.0,实现 `initialize`/`tools/list`/`tools/call` 即可,约 150-200 行 `node:readline` + JSON。
- 推荐手写;风险=自行跟踪 MCP 协议版本(锁 `protocolVersion` 如 `2024-11-05`),smoke 往返兜底。

### 关键重构:抽 `Windows/core/`(本里程碑唯一较大结构改动)
当前逻辑绑死 HTTP handler,MCP/CLI 无法复用。抽:
```
Windows/core/store.mjs    // readJson/writeJson/dataFile/resolveDataDir/emptyIndex/defaultSettings
Windows/core/lexical.mjs  // searchIndex/answerFromIndex/tokenize/...(纯函数,加 topK 形参)
Windows/core/indexer.mjs  // rebuildIndex/loadDocument/walkFiles/...
Windows/core/index.mjs    // 组合层,导出无头 API：
//   searchCore(dataDir, {query, topK=20, kinds, sourceIds})
//   answerCore(dataDir, {question, topK=8})
//   listSourcesCore(dataDir)   // 注入 documentCount(按 sourceId 聚合 index.chunks)
//   rebuildCore(dataDir)
```
- `searchIndex` 升级:`searchIndex(index, query, {kinds, sourceIds, topK})`(`slice(0,20)` → `slice(0,topK)`;`kind` 单值升级为 `kinds[]` 并兼容旧单值——实测前端 `performSearch` 不传 kind,兼容无忧)。
- `answerFromIndex` 加 `topK` 替换 hardcoded 5。
- `mneme-windows.mjs` 的 `routes` 改为**薄包装**调 core,HTTP 行为对前端不变(回归靠现有 `windows_smoke.mjs`)。**一份逻辑,三个前端(HTTP/MCP/CLI)。**

### 工具面映射(对齐 macOS DTO)
Windows chunk 缺 `uri`/`text`(只有 `path`/`snippet`),core 适配:
| MCP tool | core fn | 字段映射 |
|---|---|---|
| `mneme.search` | `searchCore` | `uri`←`pathToFileURL(path)`+`#locator`(`node:url`,纯标准库);`text`←`snippet`;其余直映 |
| `mneme.answer` | `answerCore` | `citations[]` 把 `{number,title,path,locator,kind}` **补成完整 hit**(加 `uri/score/text`) |
| `mneme.list_sources` | `listSourcesCore` | `{sourceId←id, kind, path, documentCount}` |

### CLI / 代码落点 / 打包
- `Windows/cli/mneme.mjs`(直调 core,零 HTTP):`search/answer/sources/mcp/doctor`(+可选 `rebuild`);`--json` 输出**逐字等于 MCP result schema**;`--data-dir` 透传。`doctor` 打印 dataDir/index.builtAt/chunks/documents/capabilities/Node 版本。
- 落点:`Windows/core/`、`Windows/mcp/`(`server.mjs` stdio JSON-RPC + `tools.mjs` 3 工具 schema/handler)、`Windows/cli/`、`Windows/tests/`(`mcp_smoke.mjs`/`cli_smoke.mjs`)。
- `package.json`:新 scripts `windows:mcp`/`windows:cli`/`windows:test:mcp`;`"bin": {"mneme": "Windows/cli/mneme.mjs"}`;`windows:check` 追加 `node --check` 新文件。
- 打包:electron-builder `files` 的 `Windows/**/*` 已覆盖;装好后 MCP 在 `resources/app/Windows/cli/mneme.mjs`,给 Claude Desktop 配 `node <resources>/app/Windows/cli/mneme.mjs mcp`;运行时零依赖,无需独立 node 二进制。

### 测试
仿 `windows_smoke.mjs`(`node --test` + `mkdtemp` + fixtures):core 回归(字段含 `uri/documentId/score`、topK/kinds 生效)、MCP handshake 往返(`spawn node … mcp`,验 `initialize`/`tools/list`(3 tool)/`tools/call`)、CLI(`search --json` 与 MCP schema 一致)、继续跑 `windows:test` 确认 HTTP 不变。

### 风险与待定(见主文档 §9)
手写 MCP 协议版本锁定 + smoke 兜底;`text` 语义(Windows 只有 snippet,建议 search 回 snippet、answer 回 bestSentence,需与 mac `text` 长度约定对齐);空索引时不自动 rebuild(仅 `doctor` 提示);多 reader 一致性(rebuild 原子 rename,最坏读到旧 index,文档注明无锁)。

### 粗分期
- **W2.0-a 重构地基**:抽 `Windows/core/*`、`mneme-windows.mjs` 改薄包装、`searchIndex` 加 topK/kinds。验收 `windows:test` 仍绿(对用户零行为变化)+ core 单测。**可独立合并。**
- **W2.0-b CLI** → **W2.0-c MCP**(stdio + 3 工具)→ **W2.0-d 打包/文档**(Claude Desktop config 示例)。

---

## W2.1 — 双向 agent 记忆(写回 + 索引 agent 会话)

### 目标
`mneme.remember` 写回本地记忆库 + 把 Claude/Codex 会话 `.jsonl` 作为新内容来源索引进现有词法 index,只用标准库、契约与 macOS v2.1 一致。

### 现状核对(已确认)
- **来源注册**:`addSource` 把 `{id,kind,path,addedAt}` 追加 `sources.json`,要求 `path` 是已存在目录,`kind` 经 `normalizeKind` 限定 `notes|papers|code|transcripts|activity|folder`。
- **index 结构**:`index.json = {builtAt, chunks[], stats}`;`rebuildIndex` 是**全量重建**(遍历所有 source → `loadDocument`→`chunkDocument` → 追加 transcripts → 整体 `writeJson`),**无单文档增量入口**。
- **chunk**:`{id:"<docId>#<n>", documentId, sourceId, kind, title, path, locator, text, tokens}`;`documentId = stableId(${source.id}:${filePath}:${mtimeMs})`(sha256 前 20 hex,内容变即新 id)。
- **去重**:`addSource` 按 `samePath && kind`;文档级按 `documentId`(含 mtimeMs)。
- **落盘**:Windows `%APPDATA%\Mneme`,`writeJson` 原子写。
- **写回最佳参照**:`importTranscript` **只存 `transcripts.json`,不直接改 index**;真正进 index 是 `rebuildIndex` 里把每条 transcript 合成 document(`documentId:"transcript:<id>", sourceId:"transcripts", kind:"transcript"`)走 `chunkDocument`。→ **结论:复用"数据落 JSON → rebuild 时合成 document 入 chunks"已验证模式,不要发明新索引写路径。**

### (A) 写回设计
- **存哪**:`%APPDATA%\Mneme\memory\`(与现有数据同根),一条一文件 `mem-<key>.md`,frontmatter `tags/source_ref/link/agent/title/created_at/key` + 正文。用户可在文件管理器看/删。
- **输入与去重**:`writeMemory(dataDir, {text, tags?, sourceRef?, link?, title?, agent?})`;稳定 key = `stableId(${text}|${sourceRef??""})`(复用现有 `stableId`),文件名 `mem-<key>.md`;`existsSync` 命中即视重复、返回既有记录(防 agent 反复写同文)。空 `text` 抛 `httpError(400)`(对齐 `importTranscript`)。
- **即时进 index(不依赖全量 rebuild)**:新增 `indexDocumentIncrementally(dataDir, document)`:读 `index.json` → 移除同 `documentId` 旧 chunks → `push(...chunkDocument(document))` → 重算 `stats.documents` → 原子 `writeJson`。memory 合成 document:`{documentId:"memory:<key>", sourceId:"memory", kind:"memory", title, path:<memFile>, locator:created_at, text}`(复用 transcript 已验证的"合成 document"结构,只是把入 index 时机从 rebuild 提前到写后单条)。
- **rebuild 兼容**:`rebuildIndex` 末尾(transcripts 之后)加一段扫 `memory/*.md` 解析回 document 并入 chunks,保证全量重建不丢 memory。

### (B) agent 会话索引
- **路径(Windows)**:Claude `%USERPROFILE%\.claude\projects\<slug>\*.jsonl`(`path.join(os.homedir(), ".claude", "projects")`);Codex `%USERPROFILE%\.codex\sessions\YYYY\MM\DD\rollout-*.jsonl`(递归 + 过滤,复用 `walkFiles`)。jsonl 内容格式与 mac 同,解析器应与 W2.0/mac 共享。
- **接入方式**:不写死路径,当**特殊 source kind**——`enrollAgentLogs(dataDir)` 探测根目录存在性,注册 `{kind:"agent-claude"|"agent-codex", path:<根>}` 进 `sources.json`(沿用 `addSource` 去重),会话索引完全融进 `rebuildIndex`,无需新查询路径。
- **解析成 document**:`parseAgentLog(filePath, agentName)` 逐行 `JSON.parse`,**只抽对话回合(user/assistant 文本),跳过 hook/meta/tool-result/system**,按时间拼正文,合成 `{documentId, sourceId, kind:"agent", title, path, locator, text}`。
- **id/hash**:`documentId = "agent:" + stableId(filePath + "|" + contentHash)`;`contentHash = sha256(归一化对话正文)`(续写→变→替换旧 chunk)。
- **meta**:`agent/project/session/time`。**子日志(Claude sidechain)默认跳过**,留 `includeSubagents` 开关(默认 false)。
- **关键**:`.jsonl` 已在 `TEXT_EXTENSIONS`,但通用文本读会把 hook/meta 也吞进去 → 必须在 `loadDocument` 里对 `agent-*` kind 改走 `parseAgentLog` 分支。

### 集成 / 落点 / 测试 / 风险 / 分期
- 集成:`mneme.remember` 挂 W2.0 工具面,handler 调 `writeMemory` + `indexDocumentIncrementally`,`writeResult = {key, path, deduped, indexed}`(字段对齐 mac)。若 UI 也要写回,新增 `POST /api/memory`(对齐 `/api/transcripts/import-text`),但 MCP 路径不依赖 HTTP。
- 落点(只用标准库):`Windows/core/memory.mjs`(`writeMemory/readMemoryDocuments/memoryKey`)、`Windows/core/agentLog.mjs`(`agentLogRoots/enrollAgentLogs/parseAgentLog`)、`Windows/core/indexing.mjs`(`indexDocumentIncrementally/removeDocumentChunks`);`mneme-windows.mjs`(`loadDocument` 加 agent 分支、`rebuildIndex` 加 memory+agent 段、可选 `POST /api/memory`)。
- 测试:`Windows/tests/agentMemory_test.mjs` + `Windows/fixtures/agent/`(Claude/Codex 样本各一 + 1 行 hook/meta 验跳过):写回去重(`deduped:true` 文件数不变)、增量后 `searchIndex` 命中 `kind:"memory"`、`parseAgentLog` 只产对话/跳 hook/id 稳定、端到端 `enrollAgentLogs→rebuildIndex` 搜到 `kind:"agent"`。
- 风险:**secrets 入会话日志 → 索引前轻量正则脱敏(`sk-`/`ghp_`/长 base64),见主文档 §7**;进行中会话去抖(`mtime`+`contentHash` 跳未变,最近 N 秒在写的延后,阈值待定);jsonl schema 漂移(防御解析、坏行跳过);记忆库位置(先本地库,Obsidian 导出列 P2)。
- 分期:**P0 写回**(`core/memory.mjs` + `indexDocumentIncrementally` + 挂 W2.0)→ **P1 会话索引**(`core/agentLog.mjs` + enroll + `loadDocument` 分支 + 脱敏/去抖 + fixtures)→ **P2**(Obsidian 导出、subagents 可选、`POST /api/memory` UI)。
- **未核实**:W2.0 抽出 core 的确切导出名、`mneme.remember` 的 `writeResult` 精确字段、Codex 在 Windows 的确切根目录——实现前对照 W2.0/真实日志确认。

---

## W2.2 + W2.3 — 检索质量提升 + 新来源

### W2.2 目标
把现有"伪 TF-IDF"升级为正经 BM25 + 字段加权 + CJK bigram + 邻近加分,纯标准库、无运行时第三方依赖,显著提升 search/answer。

### 现状核对(已确认,行号可核)
- **打分不是 BM25**:`searchIndex`(`:533-580`)对每 query token 累加 `tokenCounts.get(token) * termIdf`,`termIdf = log((1+N)/(1+df))+1`(`:548`);**无文档长度归一化、无 k1/b 饱和**,长 chunk 天然占优;子串命中整段 +8、标题 +4(`:560-565`)。
- **IDF 每查询 O(N·query) 全表重算**(`:542-549` 遍历 `index.chunks` 调 `chunk.tokens.includes`,无倒排)。
- **中文几乎失效**:`tokenize`(`:777-783`)`split(/[^\p{L}\p{N}_-]+/u)` 过滤 `length>1`;CJK 无空格 → **整句中文变成一个超长 token**,只靠 `normalizedQuery` 子串兜底。停用词仅 27 个英文。
- **source 抽取**:`loadDocument`(`:464-495`)读 `TEXT_EXTENSIONS`+`CODE_EXTENSIONS`;PDF 只写 3 句元数据占位(`:471-476`,坐实无 PDF 抽取);`normalizeKind`(`:814-820`)白名单。

### W2.2 方案(纯标准库,推荐全做)
- **正经 BM25**:chunk 预存 `tokenCounts` 与 `length`;建库算全局 `avgLength` 与 `df`(写进 `index.json` 顶层 `df` map + `stats.avgLength`);查询走 `idf * (tf*(k1+1))/(tf + k1*(1-b+b*len/avgLen))`,`k1=1.2, b=0.75`。同时干掉 O(N·query) 重算。
- **字段加权**:`titleTokens` 单独存,`score = bodyScore + 2.5*titleScore`(替代魔法 +4)。
- **邻近/短语**:`normalizedQuery` 子串改为 token 窗口邻近(距离≤3)小幅加分(替代粗暴 +8)。
- **CJK bigram(关键)**:`tokenize` 拆两段——拉丁走原 split;连续 CJK(`\p{Script=Han}`)切相邻**二元组**(`研究方法`→`研究/究方/方法`),query 同样 bigram,BM25 自然匹配。stdlib 下中文召回最高性价比;天花板=无真正词边界/同义。
- **停用词**:补常见中文停用词,与英文表合并。
- **向量明确不上**:引 `onnxruntime-web`/`transformers.js` = 几十~上百 MB 依赖 + 本地下载权重 + 破"只标准库" + `asar:false` 打包爆炸。**W2.2 只做 BM25+CJK**;"可选本地向量"作未来 W3.x 留口,本轮不做。

### W2.3 方案
- **Zotero → 推荐读 Better BibTeX 导出 JSON(不读 sqlite)**:(a) `better-sqlite3` 读 `zotero.sqlite` = 破"只标准库"+ 锁库,否决;(b) 只扫 `storage` PDF 但 Windows 无 PDF 抽取,价值低;(c) **用户在 Zotero 用 BBT 自动导出 `.json` 到文件夹,Mneme 当普通 source 监听**——纯 `readFile`+`JSON.parse`、零依赖、拿 title/abstract/authors/year/tags,密度最高。新 `kind:"zotero"` + `ZoteroConnector`(解析 BBT JSON 数组,每 item → `ExtractedDocument`,`text`=标题+摘要+标签,`locator`=citekey)。
- **网页剪藏(更易,先做)**:监听文件夹里 `.html`/`.md`(`.md` 已支持);`.html` 走 stdlib 正则抽正文(剥 `<script>/<style>`、取 `<title>`、`<body>` strip tags + decode entities,**不引 WebView/cheerio**)。新 `kind:"webclip"` + `WebClipConnector`(对 `.html` 插 `extractHtmlText()`)。已知天花板:正则对 SPA 不准。
- **复用现有模式**:两者只需 ① `normalizeKind`(`:816`)白名单加 `zotero`/`webclip`;② `isSupportedFile`/`inferKind`(`:705-725`)加分支;③ `addSource→rebuildIndex→searchIndex` 全程不动(对应 AGENTS.md "新增来源只加 connector")。

### 代码落点 / 接口 / 测试 / 风险 / 分期
- 落点(顺带拆 1004 行单文件,符合 200-400 行规范):`Windows/core/tokenizer.mjs`(`tokenize`+CJK bigram+停用词)、`bm25.mjs`(建库 df/avgLen + 查询打分,替换 `:533-580`)、`connectors/zotero.mjs`、`connectors/webclip.mjs`、`html_extract.mjs`;`mneme-windows.mjs` 只留 HTTP server + 路由 + 装配,import 纯函数模块。
- 接口签名:
  ```js
  export function tokenize(text)                  // 扩展现有,加 CJK 分支
  export function buildBm25Stats(chunks)          // {df: Map, avgLength, postings?}
  export function scoreBm25(chunk, queryTokens, stats, opts={k1:1.2,b:0.75,titleWeight:2.5})
  export async function extractZoteroItems(jsonPath)   // -> ExtractedDocument[]
  export function extractHtmlText(html)           // -> {title, text}
  ```
  `index.json` 加 `df` + `stats.avgLength`(向后兼容:旧库缺字段时回退原 TF 或提示 rebuild)。
- 测试(`node --test`,仿 `windows_smoke.mjs`):`tokenizer.test.mjs`(`研究方法`→含 `研究/究方/方法`、混排、停用词)、`bm25.test.mjs`(短文 vs 长文同 tf 验长度归一化、title>body、df 高权重低)、`zotero.test.mjs`(fixture BBT json 验条目/title/abstract→text/citekey→locator)、`webclip.test.mjs`(fixture `.html` 含 `<script>` 验剥脚本/正文/实体解码)+ 一个中文 query 端到端 hits≥1。fixtures 受 `package.json:31 !Windows/fixtures/**` 排除不进发行包。
- 风险:向量重依赖(本期不上,靠 capabilities 诚实降级措辞);Zotero 需用户配 BBT 自动导出(有上手成本,可能要引导文档);BM25 无倒排,`MAX_SCAN_FILES=4000` 下可接受,更大库后续上倒排;HTML 正则对 JS 渲染页无能(标注限制);旧 `index.json` 无 `df` → 首次升级提示 rebuild。
- 分期:**W2.2a BM25+字段加权+长度归一化**(替换 `:533-580`,最低风险、立即提升英文)→ **W2.2b CJK bigram+中文停用词**(解锁中文)→ **W2.3a 网页剪藏**(最易、复用度最高)→ **W2.3b Zotero BBT JSON**(需用户侧配置)。全程同步降级 capabilities/roadmap 措辞。

---

> 跨平台契约一致性、共享模式与锁定决策见主文档 [`00-roadmap.md`](00-roadmap.md)。当前 `main` 已合并 macOS V2 并保留 Windows Desktop;Windows W2.x 后续从 W2.0 core/CLI/MCP 开始。
