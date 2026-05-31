# Mneme v2 — Agent Integration:设计与 Roadmap(主文档)

- 状态:Implemented on `main` / 后续 Windows W2.x 待排期
- 日期:2026-05-29;更新:2026-05-31
- 作者:Mingjia Yang(与 Claude Scholar 协作)
- 文档性质:**设计 + 落地对照文档**。本文是 v2 的单一事实来源与整合视图;两条平台轨的里程碑明细见 [§11 子文档索引](#11-子文档索引)。

---

## 0. 一句话

> **v2 = 把 Mneme 变成本地 AI agent 的共享记忆层。**

让 Codex / Claude Code 这类 agent 通过一个**跨平台一致**的 `mneme` MCP server / CLI:**读**用户的全部本地研究语料(`search` / `answer`)、把发现**写回**(`remember`)、并把 agent 自己的会话日志也变成可检索记忆;同时顺带把检索质量和资料来源做厚。全程零运行时联网、数据不出本机。

---

## 1. 当前仓库状态

设计阶段曾发现 `develop` 与 `origin/main` 无共同祖先:macOS V2 在 `develop`,Windows Desktop 在 `main`。这个分叉已经在 `main` 的 merge commit `aea771c` 中解决;`develop` 提交 `65157ea` 是 `main` 的第二父提交。

当前 `main` 的事实:

| 领域 | 当前状态 |
|---|---|
| macOS Swift app | ✅ SwiftPM app + `MnemeCore` + `mneme` CLI/MCP helper,107 XCTest |
| Windows app | ✅ Electron + Node Desktop(`Windows/`),`npm run windows:check` + `windows:test` |
| 打包 / Assets / CI | ✅ macOS `.build/Mneme.app` bundle path + Windows installer workflow/files retained |
| 分支关系 | ✅ `main` 同时包含 Windows release line 与 macOS V2 merge parent |

- **macOS V2**:Swift,CoreML multilingual-e5 向量语义检索 + FTS5/RRF 混合检索 + MLX GUI RAG + WhisperKit 转写 + `mneme` CLI/MCP + memory/agent log/Zotero/web clips。
- **Windows Desktop**:`Windows/` 仍是 Electron 壳 + Node 后端(`mneme-windows.mjs`,只用 Node 标准库的本地 backend)。能力仍是本地词法检索 + 抽取式 Ask + transcript 文本导入 + activity 扫描;没有 CoreML 向量 / MLX / WhisperKit / 完整 PDF 抽取。

---

## 2. v2 愿景与范围

**主题**:Mneme 作为本地 agent 的记忆层,双向(读 + 写 + 记住会话)。

**平台策略(当前)**:macOS V2 已落到 `main`;Windows W2.x 仍按本文保留为后续实现设计,但现有 Windows Desktop 交付链必须继续保留并验证。

**四个能力维度,跨两个平台**:

| 维度 | macOS 轨 | Windows 轨 |
|---|---|---|
| ① Agent 接口地基 | v2.0 Swift MCP + CLI | W2.0 Node MCP + CLI |
| ② 双向记忆 | v2.1 写回 + 会话索引 | W2.1 写回 + 会话索引 |
| ③ 检索质量 | v2.2 BM25+向量混合 + 重排 | W2.2 正经 BM25 + CJK 分词(无向量,诚实降级) |
| ④ 新来源 | v2.3 Zotero + 网页剪藏 | W2.3 Zotero(BBT JSON)+ 网页剪藏 |

**非目标**(沿用产品定位 + 本轮明确):不引入运行时云服务 / 远程 embedding / 远程 LLM / telemetry;不为 Windows 引入向量栈(见 §7)。

---

## 3. 跨平台统一契约(集成脊柱)

**这是 v2 最重要的整合约束**:无论 macOS(Swift)还是 Windows(Node),对外暴露的 MCP 工具面、CLI 和 JSON DTO **必须逐字一致**,这样 agent 看到的是同一个 `mneme`,不分平台。

### MCP 工具(stdio JSON-RPC)

```jsonc
// mneme.search
in : { "query": string, "topK"?: int=20, "kinds"?: string[], "sourceIds"?: string[] }
out: { "hits": [ { "score": number, "title"?: string, "uri": string, "sourceURL"?: string,
                   "kind": string, "text": string, "documentId": string,
                   "locator"?: { page?, startChar?, endChar?, startLine?, endLine? } } ] }

// mneme.answer        （CLI/MCP 默认 extractive；macOS GUI 可用 MLX 本地生成）
in : { "question": string, "topK"?: int=8, "kinds"?: string[], "sourceIds"?: string[] }
out: { "answer": string, "citations": [ <同 hit schema> ] }

// mneme.list_sources
out: { "sources": [ { "sourceId": string, "kind": string, "path": string, "documentCount": int } ] }

// mneme.remember      （v2.1 引入）
in : { "text": string, "tags"?: string[], "sourceRef"?: string, "link"?: string, "title"?: string }
out: { "key": string, "path": string, "deduped": bool, "indexed": bool }
```

### CLI(与 MCP 复用同一核心,`--json` 输出与 MCP result schema 同构)

```
mneme search  <query>    [--top-k 20] [--kinds notes,code] [--source-ids ...] [--json]
mneme answer  <question> [--top-k 8]                                   [--json]
mneme sources                                                          [--json]
mneme mcp        # 启动 stdio MCP server
mneme doctor     # 打印 数据目录 / 文档数 / embedder_id+dim(mac) / capabilities / 运行时版本
mneme rebuild    # 可选未来项：headless 触发重建索引
```

### agent 侧注册(两平台形态一致)

```jsonc
// Claude Code / Codex 的 MCP 配置
{ "mcpServers": { "mneme": { "command": "mneme", "args": ["mcp"] } } }
// Windows 若用 node 入口： "command": "node", "args": ["<app>/Windows/cli/mneme.mjs", "mcp"]
```

---

## 4. 共享架构模式(两平台同构的设计决策)

整合后发现,两条轨在四件事上做了**同构选择**,应作为统一原则贯彻:

1. **核心抽取(core extraction)**:对外接口前,先把可复用逻辑抽成一层。
   - macOS:把 `CoreMLE5*` / `NLEmbedding` 从 App target **下沉进 `MnemeCore`**,新增 `MnemeQueryFacade` + Codable DTO 作为 MCP/CLI 唯一调用面。
   - Windows:把绑死在 HTTP handler 闭包里的 `searchIndex/answerFromIndex/rebuildIndex` 抽成 `Windows/core/*.mjs`,供 HTTP server + MCP + CLI 三者共用(DRY)。
2. **独立进程 + 读同一份数据**(两平台都**否决**了"瘦客户端连常驻 app"):
   - macOS:`mneme` 独立二进制**只读**打开同一 `index.sqlite`(headless 可用)。
   - Windows:`mneme` 独立 Node 进程读同一 `%APPDATA%\Mneme\*.json`(Electron 内端口是 `port:0` 随机分配,无法稳定连,这也佐证独立进程是对的)。
3. **手写 stdio MCP,守住最小依赖**:两平台都倾向**不引入 MCP SDK**——Windows 为守"只用标准库"手写 stdio JSON-RPC(约 150–200 行,仅 `initialize`/`tools/list`/`tools/call`);macOS 同理倾向手写以保持零/最小新增依赖(见 §9 待定项)。
4. **记忆 = 受管文件 + 即时单条索引**:
   - 两平台都把 `remember` 落成**受管 Markdown 文件**(mac:专属 `.md` 目录;win:`%APPDATA%\Mneme\memory\*.md`),frontmatter 带 `tags/source_ref/link/agent`,稳定 key = `hash(text|sourceRef)` 去重,写后走**单条增量索引**(mac:抽 `IndexingPipeline.indexOne`;win:`indexDocumentIncrementally`),复用各自已验证的"产物落盘→索引"模式(mac 的 ActivityConnector / win 的 transcript 导入是先例)。
5. **agent 会话格式跨平台一致**:Claude Code(`.claude/projects/<slug>/*.jsonl`)与 Codex(`.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`)的 jsonl 格式两平台相同,只是根目录/分隔符不同。解析逻辑(只抽对话回合、跳过 hook/meta、防御式解析)两轨同构。

---

## 5. 已锁定的关键决策

| # | 决策 | 影响范围 | 备注 |
|---|---|---|---|
| D1 | **macOS `IndexStore` 现在切 WAL** | mac v2.0 地基 | 单写多读:agent 只读不撞 GUI 写、headless 写回(v2.1)能即时索引。落地验证至少跑 107 XCTest + bundle/CLI/MCP smoke。 |
| D2 | **`answer` 默认 extractive** | 两平台 | CLI/MCP 零模型零联网;macOS GUI 保留 MLX 本地生成;Windows 本就只有 extractive,天然一致。 |
| D3 | **平台范围:macOS V2 已落地,Windows W2.x 保持后续设计** | 全局 | main 当前同时保留 macOS V2 与 Windows Desktop。 |
| D4 | **develop↔main 分叉已通过 merge commit 解决** | 全局 | `aea771c` 以 `develop` 的 `65157ea` 为第二父提交,同时保留 main-only Windows 文件。 |
| D5 | **MCP 传输 = stdio + 手写 JSON-RPC** | 两平台 | macOS 已手写实现;Windows W2.x 若实现 MCP,仍按标准库手写方向。 |

---

## 6. 里程碑 Roadmap

### macOS 轨(已落地,当前在 `main`)

| 里程碑 | 内容 | 依赖 | 关键风险(已核实) |
|---|---|---|---|
| **v2.0** Agent 接口地基 | 独立 `mneme` 二进制:`mneme mcp`(stdio,4 tool)+ `search/answer/sources/remember/doctor` CLI;**迁 embedding 入 MnemeCore**;`IndexStore` 只读 init + **切 WAL** | 无 | 已通过 107 XCTest、helper CLI/MCP smoke、bundle smoke |
| **v2.1** 双向记忆 | `mneme.remember` 写受管 `.md` 记忆库 + `AgentTranscriptConnector` 索引 Claude/Codex 会话;`SourceKind` 加 `.memory`/`.agentSession`;抽 `IndexingPipeline.indexOne` | v2.0 工具面 + WAL 写路径 | 会话日志含 secrets→redaction;进行中会话去抖 |
| **v2.2** 检索质量 | FTS5(BM25)+ RRF 融合(k=60)+ CJK bigram;eval 扩 Hit@5/MRR 守门 | 独立(改 IndexStore/QueryService) | **迁移经核实无损**(FTS `IF NOT EXISTS`+一次 rebuild 回填,不触发 `*.incompatible`);默认 hybrid,本期不引重排模型 |
| **v2.3** 新来源 | `ZoteroConnector`(只读复制 `zotero.sqlite`)+ `WebClipConnector`(本地 HTML/Markdown/TXT 剪藏);`SourceKind` 加 `.zotero`/`.web`;抽 `PDFTextExtractor` | 独立(纯加 connector) | 已选择纯 Swift/正则抽取,不走 WKWebView |

**顺序**:v2.0 → v2.1 → v2.2 → v2.3。v2.3 网页剪藏风险最低,可作为"快速可见成果"提前插队。

### Windows 轨(设计完成,现有 Desktop 已保留, W2.x 后续跟进)

| 里程碑 | 内容 | 依赖 | 关键风险(已核实) |
|---|---|---|---|
| **W2.0** Node MCP + CLI 地基 | **抽 `Windows/core/`**(唯一较大重构)+ 独立 Node 进程 + 手写 stdio JSON-RPC MCP + `mneme` CLI;`searchIndex` 加 `topK`/`kinds` | 无 | HTTP 逻辑绑死在 handler 闭包需先抽出;MCP 协议版本手写需 smoke 兜底 |
| **W2.1** 双向记忆 | `mneme.remember` 写 `%APPDATA%\Mneme\memory\*.md` + `indexDocumentIncrementally`;agent 会话作为特殊 source kind 接入 `rebuildIndex` | W2.0 core | secrets redaction;进行中会话去抖;rebuild 全量重建无单文档增量(需新增) |
| **W2.2** 检索质量 | 现状是**伪 TF-IDF**:升级正经 BM25(k1=1.2,b=0.75)+ 字段加权 + **CJK bigram**(当前整句中文=一个 token,中文检索基本失效)+ 中文停用词 | 独立 | **明确不引向量**(破"只标准库"+ 打包爆炸);天花板=lexical-only,结构性弱于 mac |
| **W2.3** 新来源 | Zotero 经 **Better BibTeX JSON 导出**(不读 sqlite,避免破"只标准库"+ 锁库)+ 网页剪藏(`.html` 正则抽正文,无 WebView) | 独立(纯加 connector) | Zotero 需用户配 BBT 自动导出;HTML 正则对 SPA 不准 |

**顺序**:W2.0 → W2.1 → W2.3(网页易、先做)→ W2.2(检索升级)。可与 macOS 轨并行排期。

---

## 7. 跨里程碑 / 跨平台风险

1. **agent 会话日志含密钥**(两平台 W/v2.1):Claude/Codex jsonl 可能含 `sk-`/`ghp_`/长 base64 等。**统一策略**:索引前做轻量正则脱敏 + 默认不索引明显 secret 字段;会话/记忆都是明文落盘在用户 profile,用户可见可删。**需定 redaction 规则(见 §9)**。
2. **Windows 检索天花板**(W2.2):Windows 纯 lexical,无语义召回,"换个说法问同一件事"会漏。**整合要求:在 `capabilities()` / README / roadmap 用诚实措辞标注 "Windows search/answer is lexical-only and below the macOS hybrid build",不制造平价错觉。**
3. **schema 迁移**:mac v2.0 切 WAL(动写路径,重验基线)、v2.2 加 FTS5(无损,但首库 rebuild 回填有耗时,需进度提示);win W2.2 给 `index.json` 加 `df`/`avgLength`(旧库需 rebuild,首次升级提示用户)。
4. **分支分叉已解决**(D4):当前 `main` 已同时包含 macOS V2 与 Windows Desktop;后续只需保持双平台验证一起跑。
5. **Zotero 取数方式两平台不同**(可接受的分歧):mac 复制 `zotero.sqlite` 只读;win 走 BBT JSON 导出(因 Node 读 sqlite 要破"只标准库")。对外 `kind=zotero` 一致,实现分歧不影响契约。

---

## 8. 验证基线

- **macOS**:`DEVELOPER_DIR=… swift test`(当前 107 XCTest);`swift build`;`scripts/build_app_bundle.sh`;`plutil -lint`;`codesign --verify --deep --strict`;bundled helper `mneme doctor`;MCP `initialize/tools/list/remember/search` smoke;`.build/Mneme.app/Contents/MacOS/Mneme` 5 秒启动 smoke;确认无残留 Mneme/mneme 进程。
- **Windows**:`npm run windows:check`;`npm run windows:test`;Windows installer workflow/files保留。W2.x MCP/CLI 尚未实现前,不要把 Windows MCP handshake 当作当前通过标准。

---

## 9. 待你拍板的剩余开放问题

> 这些不阻塞写设计文档,但实现前需明确。建议放进各里程碑实现计划(writing-plans)时逐一确认。

- **[mac v2.0 已定]** CLI 采用手写解析,未新增 `swift-argument-parser`。
- **[mac v2.0 已定]** `CoreMLE5*`/`NLEmbedding` 已下沉 MnemeCore 装配路径。
- **[mac v2.0 已定]** `list_sources` 读配置并结合索引文档计数;CLI/GUI 共用 `SourcesReader`。
- **[mac v2.2 已定]** `QueryService.search` 默认 `.hybrid`。
- **[mac v2.2 已定]** 当前只做 FTS5+RRF,不引入新的重排模型。
- **[win W2.0]** 手写 MCP(锁 `protocolVersion` 字符串 + smoke 兜底)vs 破"只标准库"引官方 SDK?(建议手写)
- **[win W2.0]** headless 检测到空索引时是否自动 `rebuild`?(建议否,仅 `doctor`/错误提示)
- **[两平台 v2.1/W2.1]** agent 会话 redaction 规则的具体形态(正则集 + 是否 opt-in)。
- **[win W2.2]** 未来是否接受可选本地向量(`onnxruntime-web`,破"只标准库")作为 W3.x;本轮明确不做。

---

## 10. 下一步

1. 保持 `main` 的双平台落地验证一起跑:107 XCTest + Swift build + app bundle/CLI/MCP smoke + Windows `windows:check`/`windows:test`。
2. Windows W2.x 若进入实现,按 [`20-windows-track-design.md`](20-windows-track-design.md) 从 W2.0 core/CLI/MCP 开始。
3. 后续 release 前再补真实用户库 smoke:真实 e5 模型、真实 Zotero 库、真实 MCP client handshake、真实 Windows runner artifact。

---

## 11. 子文档索引

- macOS 轨四里程碑明细 → [`10-macos-track-design.md`](10-macos-track-design.md)
- Windows 轨明细(W2.0 / W2.1 / W2.2+W2.3)→ [`20-windows-track-design.md`](20-windows-track-design.md)
- 既有产品设计(v1)→ [`../00-product-design.md`](../00-product-design.md)、模块 spec [`../01-module-index-query.md`](../01-module-index-query.md) 等
