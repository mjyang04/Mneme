# Mneme 产品总体设计

- 状态:Design / 待评审
- 日期:2026-05-29
- 作者:Mingjia Yang(与 Claude Scholar 协作)
- 适用环境:macOS 14+ Apple Silicon 为正式打包目标;Windows 10/11 为 Desktop build 目标(Node.js 22+ / Electron)

---

## 1. 目标与非目标

### 目标
- 把分散在本机的研究材料(Obsidian 笔记、论文 PDF、代码、语音转写、活动日志)**统一为可语义检索的本地索引**。
- 提供**零延迟的随手入口**:全局热键 → 快搜悬浮窗。
- **完全离线**:运行时不发任何网络请求(模型权重仅首次本地准备/下载一次)。
- 自用趁手优先,实用 > 花哨。

### 非目标(本版明确不做)
- 不做云同步、不做多人协作、不做账号体系。
- 不把 Windows Desktop 宣称为已具备 macOS 的全部模型能力;本轮落地桌面壳、installer path、来源扫描、搜索/Ask、转写文本导入和 activity scan。
- 不做通用文件管理器/笔记编辑器(不抢 Obsidian 的活,只做检索与捕获)。
- 不做 App Store 上架打磨(自用,开发签名即可)。

---

## 2. 总体架构

统一产品,三个模块共享同一套核心层。模块②③是「内容来源」,模块①是覆盖全部内容的「查询层」。

```
┌─────────────────────────── UI 层 ─────────────────────────────────────┐
│  macOS: SwiftUI MenuBarExtra │ 全局热键 → QuickSearch(NSPanel)          │
│  Windows Desktop: Electron window/tray + 本地 Node.js backend            │
│  共享信息结构:Search/Ask │ Sources │ Transcripts │ Activity │ Settings   │
└───────────────────────────────────┬────────────────────────────────────┘
                                     │ (调用,@MainActor 之外)
┌──────────────────────────────── 共享核心层 ─────────────────────────────┐
│  SourceConnector 协议(可插拔内容来源)                                     │
│    ├─ NotesConnector      (Obsidian .md)                                 │
│    ├─ PDFConnector        (PDFKit + Vision OCR 兜底)                      │
│    ├─ CodeConnector       (源码文件)                                      │
│    ├─ TranscriptConnector ◄── 模块②                                       │
│    └─ ActivityConnector   ◄── 模块③                                       │
│                                                                          │
│  Chunker            把文档切成带元数据的 chunk                            │
│  EmbeddingService   CoreML 多语 embedding(走 ANE)                       │
│  IndexStore (actor) GRDB/SQLite + sqlite-vec;向量增删查                  │
│  IndexingPipeline   监听 → 抽取 → 分块 → 向量化 → 增量 upsert            │
│  QueryService       语义检索 →(phase2)本地 LLM RAG 带引用              │
│  ModelManager       embedding / LLM / whisper 模型生命周期               │
│  BookmarkStore      security-scoped bookmarks 持久化文件夹授权           │
└──────────────────────────────────────────────────────────────────────────┘
```

### 平台边界
- macOS 是 v0.1.0 正式打包平台:`.app` + DMG,使用 SwiftUI/AppKit/CoreML/MLX/WhisperKit/FSEvents/SMAppService。
- Windows 当前是 Desktop build:Electron 启动原生窗口/托盘/`Ctrl+Space` 全局快捷键,内嵌本地 Node.js backend;运行期数据默认落在 `%APPDATA%\Mneme`。
- Windows Desktop 已覆盖来源注册、本地文本/代码/笔记索引、PDF metadata indexing、lexical search、extractive Ask 引用回答、transcript text import、activity scan、原生 folder picker 和 installer artifact path。
- Windows 尚未覆盖 CoreML e5、MLX 生成、WhisperKit 音频转写和完整 PDF 文本抽取。

### 分层原则
- UI 层不直接碰存储与模型,只经由 service 对象(便于测试、便于换实现)。
- 核心层每个单元单一职责、接口清晰、可独立测试。
- 模块通过 `SourceConnector` 协议接入,新增来源 = 新增一个 connector,不动核心。

---

## 3. 核心组件职责

| 组件 | 职责 | 依赖 |
|---|---|---|
| `SourceConnector`(protocol) | 枚举来源条目、抽取纯文本 + 元数据、给出稳定 id 与内容指纹 | 文件系统 |
| `Chunker` | 按策略把长文本切块(markdown 感知 / 代码块 / 固定窗口+overlap) | 无 |
| `EmbeddingService` | 文本 → 向量;批处理;query/passage 前缀约定 | CoreML 模型 |
| `IndexStore`(actor) | chunk 与向量的增删查;按 `sourceId+contentHash` 去重;topK 检索 | GRDB, sqlite-vec |
| `IndexingPipeline` | 编排「监听→抽取→分块→向量化→upsert」,支持增量与断点续跑 | 上述全部 |
| `QueryService` | 检索 API、去重排序、结果模型;phase2 RAG 编排 | IndexStore, (LLM) |
| `ModelManager` | 下载/加载/卸载 embedding、LLM、whisper 模型,内存压力下卸载 | 文件系统 |
| `BookmarkStore` | 持久化用户授权的文件夹(沙箱外访问) | UserDefaults/Keychain |

---

## 4. 数据模型(SQLite)

```sql
-- 来源(用户授权的文件夹或集合)
CREATE TABLE sources (
  id            TEXT PRIMARY KEY,      -- uuid
  kind          TEXT NOT NULL,         -- notes | pdf | code | transcript | activity
  root_bookmark BLOB,                  -- security-scoped bookmark(文件夹来源)
  display_name  TEXT NOT NULL,
  enabled       INTEGER NOT NULL DEFAULT 1,
  created_at    REAL NOT NULL
);

-- 文档(一个文件 / 一段转写 / 一天的活动)
CREATE TABLE documents (
  id            TEXT PRIMARY KEY,      -- 稳定 id(来源相关)
  source_id     TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  uri           TEXT NOT NULL,         -- file:// 或自定义 scheme
  title         TEXT,
  content_hash  TEXT NOT NULL,         -- 内容指纹,用于增量去重
  modified_at   REAL,
  indexed_at    REAL,
  meta_json     TEXT                   -- 来源特有元数据(页码范围、tags、frontmatter…)
);

-- chunk(检索与展示的最小单元)
CREATE TABLE chunks (
  id            TEXT PRIMARY KEY,
  document_id   TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  ordinal       INTEGER NOT NULL,      -- 文档内序号
  text          TEXT NOT NULL,
  locator_json  TEXT                   -- 定位信息(行号 / 页码 / 时间戳区间)
);

-- 向量(sqlite-vec 虚表;维度随模型固定)
CREATE VIRTUAL TABLE chunk_vec USING vec0(
  chunk_id      TEXT PRIMARY KEY,
  embedding     FLOAT[384]             -- e.g. multilingual-e5-small = 384 维
);
```

> 设计要点:`documents.content_hash` 是增量索引的关键——重扫时哈希未变则跳过;变了则删旧 chunk/向量后重建。`chunks.locator_json` 决定「点击结果能精确跳回原文何处」。

---

## 5. 技术选型

| 关注点 | 选型 | 备注 |
|---|---|---|
| 壳 | macOS: SwiftUI + `MenuBarExtra`; Windows Desktop: Electron window/tray + Node backend | macOS 悬浮窗用 `NSPanel`;Windows 用 Electron shell |
| 全局热键 | `KeyboardShortcuts`(sindresorhus) | 用户可在设置里改键 |
| 开机自启 | `SMAppService`(macOS 13+) | 登录项 |
| Embedding | **CoreML** 跑 `multilingual-e5-small`(384d) | 走 ANE,常驻省电;中英混合 |
| 向量库 | GRDB.swift + `sqlite-vec`(asg017) | v1 也可 `vDSP` 暴力余弦兜底 |
| 本地 LLM(②阶段) | **MLX-swift** 跑 `Qwen2.5-3B-Instruct` 或 `Llama-3.2-3B`(4-bit) | M5 Pro 可跑 7B,默认 3B 求快 |
| 语音转写(模块②) | **WhisperKit**(argmaxinc) | 纯 Swift + CoreML,多语 |
| PDF | PDFKit 抽文本 + Vision `VNRecognizeTextRequest` | 扫描版走 OCR 兜底 |
| 文件监听(模块③) | macOS: FSEvents; Windows Desktop: manual activity scan | 后续 Windows 原生 watcher 再补 |
| git 解析(模块③) | shell 调 `git log --since` 或 SwiftGit2 | v1 优先 shell,零依赖 |
| 写回 Obsidian | 直接写 `.md` + YAML frontmatter | 受管段落用标记,避免覆盖用户编辑 |

### embedding 模型选型理由
- e5 系列需要 `query:` / `passage:` 前缀,检索质量好且小;multilingual 版覆盖中英。
- 384 维向量库小、检索快;数万~数十万 chunk 在 sqlite-vec / vDSP 下都是毫秒级。
- 走 CoreML 而非 MLX 做 embedding:常驻后台时 ANE 比 GPU 更省电,适合「时刻可查」。

---

## 6. 并发模型

- `IndexStore` 为 `actor`,串行化所有写入,避免 SQLite 并发写问题。
- 索引为后台任务:`Task.detached` + 优先级 `.utility`,不阻塞 UI。
- `EmbeddingService` 批量推理,单批限流,避免内存峰值。
- 查询路径 `@MainActor` 只负责收尾渲染;检索与向量化在后台。
- 监听去抖:FSEvents 事件先入队,空闲窗口(如 2s)聚合后再触发增量索引。

---

## 7. 隐私与权限

- **零运行时联网**:除「首次准备模型权重」外,任何路径都不发网络请求。可在设置里显示「网络:已禁用」状态以自证。
- **文件夹授权**:用户在「来源」里选文件夹,用 security-scoped bookmark 持久化;启动时 `startAccessingSecurityScopedResource()`。
- **沙箱取舍(自用)**:默认**不开 App Sandbox** 的开发签名构建,任意文件夹直读最省事。若日后要分发,再切到沙箱 + bookmarks 完整路径。
- 索引库、模型、缓存全部落在本机。macOS 使用 `~/Library/Application Support/Mneme/`;Windows Desktop 默认使用 `%APPDATA%\Mneme`;都应可一键清空。

---

## 8. 错误处理策略

| 场景 | 处理 |
|---|---|
| 文件夹授权失效(bookmark stale) | 标记来源「需重新授权」,UI 引导用户重选 |
| embedding 模型加载失败 | 告警并暂停索引;可选降级到 `NLEmbedding` 的**独立**索引(维度不同,不与主索引混维,详见模块① §5) |
| 扫描版 PDF 抽不到文本 | 走 Vision OCR;OCR 仍失败则跳过该文档并记入「索引问题」列表 |
| 单文件解析异常 | 局部失败不影响整体管道;失败计入 `documents` 的问题标记,可单独重试 |
| 索引中断/崩溃 | 增量基于 `content_hash`,重启后从未完成处继续,不重复已完成项 |
| 向量库损坏 | 提供「重建索引」操作;模型与原文都在,可全量重建 |

原则:**局部失败可恢复、可见、可重试**;绝不静默吞错(记入可见的「索引问题」面板 + 日志)。

---

## 9. 测试策略

- **单元测试**
  - `Chunker`:给定文本与策略,验证块数、边界、overlap、locator 正确。
  - `IndexStore`:写入已知向量,验证 topK 检索命中与排序;验证按 hash 去重与级联删除。
  - 各 `Connector`:对 fixture 文件(md/pdf/code)验证抽取文本与元数据。
- **集成测试**
  - 索引一个 fixture vault(几十个 md/pdf)→ 跑预设查询 → 断言 top1/topK 命中预期文档。
- **Retrieval eval(贴合你的实验习惯)**
  - 维护 `eval/queries.jsonl`(query → 期望命中 doc/chunk id),CI 跑 **Hit@5 / MRR**,设阈值守住检索回归(参考你过往 Hit@5=1.00、MRR≈0.94 的标准)。
- **手动冒烟**
  - 真实库索引 → 热键唤起 → 中英查询 → 点击跳回原文。

---

## 10. 建造分期(每期可独立交付)

| 期 | 内容 | 交付物 |
|---|---|---|
| **P0** | 脚手架:菜单栏 + 主窗口壳、设置、文件夹授权(bookmarks)、SQLite/GRDB 初始化、`ModelManager` 骨架 | 能跑的空壳 app |
| **P1** | **模块①核心**:Notes/PDF/Code 连接器 → Chunker → CoreML embedding → IndexStore → 热键悬浮窗**语义搜索** | **第一个可用版本** |
| **P2** | **模块①-RAG**:接入 MLX 本地 LLM,检索片段 → 带引用问答 | 能「问」而不只是「搜」 |
| **P3** | **模块③**:FSEvents+git → 每日 Obsidian 日志 + 活动浏览;ActivityConnector 汇入索引 | 自动 research log |
| **P4** | **模块②**:macOS WhisperKit 转写 → TranscriptConnector 汇入索引 + 转写管理 + 导出;Windows Desktop 先做 transcript text import | 语音/转写文本也可检索 |
| **P5** | **Windows runtime hardening**:补 watcher、PDF text extraction、可替代 embedding/LLM/transcription runtime | Windows 功能补齐 |

> 顺序逻辑:①是地基(②③的内容都要经它检索);③比②轻(纯 Swift)故先于②;P2(RAG)可视精力在 P3/P4 之间灵活插入。

---

## 11. 关键假设(待确认)

1. 开发机 **M5 Pro**,内存足以同时跑 embedding 常驻 + 按需 3–7B LLM。
2. 最低正式发布目标 **macOS 14**(用最新 SwiftUI / MenuBarExtra / SMAppService);Windows Desktop 目标 Windows 10/11 + Node.js 22+。
3. 内容**中英混合** → 多语 embedding + Whisper 多语。
4. 数据来源全部**可配置文件夹**,不硬编码任何路径。
5. 自用场景,**先不上 App Sandbox**;模型权重首次本地准备一次可接受。
6. 产品名 **Mneme** 为 working name,可改。

---

## 12. 模块 spec 索引

- 模块① → [01-module-index-query.md](01-module-index-query.md)
- 模块② → [02-module-transcription.md](02-module-transcription.md)
- 模块③ → [03-module-activity-log.md](03-module-activity-log.md)
