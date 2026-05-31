# Mneme

Mneme is a local-first research memory app. The current packaged release is for macOS, and this repository also includes a Windows Desktop build path with an Electron shell, tray entry, global shortcut, local backend, and installer artifacts produced on Windows CI.

Mneme does not require programming experience. Install the app, choose the folders you want Mneme to read, build the local index, and use the quick-search window or main app tabs.

## Platform Status

| Platform | Status | Entry point |
| --- | --- | --- |
| macOS | Packaged v0.1.0 release for Apple Silicon Macs | `Mneme-v0.1.0-macos-arm64.dmg` |
| Windows | Desktop build with CI-generated installer artifacts | `npm run windows:dev` for development; `npm run windows:dist` on Windows for installer artifacts |

## Download

Download the latest installer from the [Releases](https://github.com/mjyang04/Mneme/releases) page.

Use the macOS DMG installer:

1. Open `Mneme-v0.1.0-macos-arm64.dmg`.
2. Drag `Mneme.app` into `Applications`.
3. Open `Mneme.app` from `Applications`.

Mneme v0.1.0 is a free ad-hoc signed build and is not notarized by Apple. If macOS blocks the first launch, follow [INSTALL.md](INSTALL.md). You usually only need to approve it once.

Windows Desktop development run:

```powershell
npm ci
npm run windows:dev
```

The Windows app stores runtime data under `%APPDATA%\Mneme`. See [Windows/README.md](Windows/README.md) for the desktop app, installer build, tests, and current runtime limits.

## Requirements

- Apple Silicon Mac, M1 or newer.
- macOS 14 or newer.
- Windows Desktop: Windows 10/11 with Node.js 22 or newer for development builds. Packaged artifacts are built by the Windows CI workflow.
- Enough local disk space for app data and local models. Optional transcription and local answer models may use several hundred MB or more.
- Internet access is recommended on first use so Mneme can prepare optional local models. After model preparation, normal indexing and search stay local.

## First Use

macOS:

1. Open Mneme from `Applications`.
2. Add folders in Settings:
   - Notes folders for Markdown notes.
   - Paper folders for PDF files.
   - Code folders for source repositories.
   - Web clip folders for saved HTML/Markdown clips.
   - Zotero library folders when you want Mneme to index Zotero metadata.
   - Agent log folders when you explicitly want local Claude/Codex session logs indexed.
3. Click **Rebuild Index**.
4. Use the menu-bar item or global quick-search shortcut to search.
5. In the Transcripts tab, choose an audio file and start transcription. If the WhisperKit model is not installed yet, Mneme can download it automatically.
6. In the Activity tab, choose workspace folders and a daily-note folder if you want Mneme to write daily activity summaries.

Windows Desktop:

1. Install the Windows artifact produced by the `Windows Desktop` workflow, or run `npm run windows:dev` during development.
2. Open Mneme from the Start menu or tray.
3. Add source folders in the Sources tab, using **Browse** for the native folder picker.
4. Rebuild the index, then use Search / Ask or the `Ctrl+Space` global shortcut.
5. Import transcript text or refresh Activity from the desktop workbench.

## What Mneme Stores Locally

Mneme stores runtime data locally:

- Search index database.
- Transcript JSON files.
- Local model cache.
- Source folder settings and bookmarks.
- Generated activity-note content when the user enables Activity Log write-back.

On macOS this is under the user's Application Support folder. On Windows Desktop builds this is under `%APPDATA%\Mneme` unless `MNEME_WINDOWS_DATA_DIR` or `--data-dir` is set for backend development.

Mneme does not include cloud sync, hosted inference, analytics, or telemetry.

## Local Agent Interface

The app bundle includes a headless `mneme` command at:

```bash
/Applications/Mneme.app/Contents/Helpers/mneme
```

Useful commands:

```bash
mneme doctor --json
mneme search "query" --json
mneme answer "question" --json
mneme remember "short memory text" --tags research,agent --json
mneme mcp
```

For MCP clients, register the same executable with `args: ["mcp"]`. Any agent granted access to this MCP server can read the indexed local corpus, so only register it with agents you trust.

## Main Features

- Menu-bar app with a main window and quick-search panel.
- Local indexing for notes, PDFs, source code, transcripts, and activity notes.
- Local indexing for managed memories, selected agent logs, Zotero metadata, and saved web clips.
- Local semantic search with CoreML multilingual embeddings.
- Hybrid retrieval combines local semantic vectors with FTS5 lexical search and CJK bigram matching.
- Local RAG answers with citations using MLX, with a local fallback answer path.
- `mneme` CLI/MCP interface for local agents: `search`, `answer`, `sources`, `remember`, `doctor`, and `mcp`.
- Local WhisperKit transcription, transcript indexing, Obsidian export, and timestamp playback.
- Activity Log for workspace changes and git activity, with optional local daily summaries.
- Source-folder watching, configurable global shortcut, and launch-at-login support.
- Windows Desktop app with native window, tray entry, `Ctrl+Space` global shortcut, native folder picker, Sources, Search / Ask, Transcripts, Activity, and Settings using local source scanning and extractive citations.

## Current Release

v0.1.0 is the first public macOS release. It is suitable for local testing and early daily use, with the following practical limits:

- Very large research corpora may need more validation.
- Long recordings may require time and local disk space.
- Mixed-language recordings and scanned PDFs should be checked on representative user files.
- Optional local models may download on first use and depend on network availability during setup.
- Windows now has a desktop packaging path with installer artifacts from CI. It supports local folder indexing, search, extractive Ask answers, transcript text import, activity scanning, native tray/window shell, native folder picker, and `Ctrl+Space` global shortcut. CoreML e5, MLX generation, WhisperKit audio transcription, and full PDF text extraction remain macOS-only or future Windows runtime work.

See [RELEASE_NOTES.md](RELEASE_NOTES.md) for unreleased Windows Desktop notes.

## License

Mneme is open source under the [MIT License](LICENSE).

---

# Mneme 中文用户指南

Mneme 是一款本地优先的科研记忆应用。当前正式打包发布的是 macOS 版本；仓库内也包含 Windows Desktop 构建路径，使用 Electron 桌面壳、本地 backend、托盘入口、全局快捷键，并通过 Windows CI 产出 installer artifact。

使用 Mneme 不需要编程经验。下载安装应用后，选择要读取的资料文件夹，建立本地索引，然后使用快速搜索窗口或主窗口中的各个功能页。

## 平台状态

| 平台 | 状态 | 入口 |
| --- | --- | --- |
| macOS | Apple Silicon Mac 的 v0.1.0 打包版本 | `Mneme-v0.1.0-macos-arm64.dmg` |
| Windows | Desktop build，通过 CI 产出 installer artifact | 开发运行 `npm run windows:dev`；Windows 上打包 `npm run windows:dist` |

## 下载

从 [Releases](https://github.com/mjyang04/Mneme/releases) 页面下载最新版安装包。

使用 macOS DMG 安装：

1. 打开 `Mneme-v0.1.0-macos-arm64.dmg`。
2. 将 `Mneme.app` 拖入 `Applications`。
3. 从 `Applications` 打开 `Mneme.app`。

Mneme v0.1.0 是免费发布的 ad-hoc signed 构建，没有经过 Apple notarization。如果 macOS 首次启动时拦截应用，请按 [INSTALL.md](INSTALL.md) 操作；通常只需要批准一次。

Windows Desktop 开发运行：

```powershell
npm ci
npm run windows:dev
```

Windows app 默认把运行期数据保存在 `%APPDATA%\Mneme`。桌面 app、installer build、测试方法和当前 runtime 限制见 [Windows/README.md](Windows/README.md)。

## 系统要求

- Apple Silicon Mac，M1 或更新芯片即可。
- macOS 14 或更新版本。
- Windows Desktop：开发构建需要 Windows 10/11 和 Node.js 22 或更新版本；打包 artifact 由 Windows CI workflow 生成。
- 需要足够的本地磁盘空间存放应用数据和本地模型。可选的转写模型和本地问答模型可能占用数百 MB 或更多空间。
- 首次使用建议保持网络连接，Mneme 可以自动准备可选本地模型。模型准备完成后，日常索引和搜索都在本机运行。

## 首次使用

macOS：

1. 从 `Applications` 打开 Mneme。
2. 在 Settings 中添加资料来源：
   - Notes folders：Markdown 笔记。
   - Paper folders：PDF 文件。
   - Code folders：代码仓库。
   - Web clip folders：本地保存的网页剪藏。
   - Zotero library folders：需要索引 Zotero 元数据时选择 Zotero 库。
   - Agent log folders：只有在你明确希望索引 Claude/Codex 本地会话日志时添加。
3. 点击 **Rebuild Index** 建立本地索引。
4. 通过菜单栏或全局快捷键打开快速搜索。
5. 在 Transcripts 页选择音频文件并开始转写。如果 WhisperKit 模型尚未安装，Mneme 可以自动下载。
6. 如果需要活动日志，在 Activity 页选择 workspace folders 和 daily-note folder，让 Mneme 写入每日活动摘要。

Windows Desktop：

1. 安装 `Windows Desktop` workflow 产出的 Windows artifact，或开发时运行 `npm run windows:dev`。
2. 从 Start menu 或 tray 打开 Mneme。
3. 在 Sources tab 添加资料来源文件夹，可用 **Browse** 打开原生文件夹选择器。
4. Rebuild index，然后使用 Search / Ask 或 `Ctrl+Space` 全局快捷键。
5. 可在桌面工作台中导入 transcript text 或刷新 Activity。

## Mneme 会在本机保存什么

Mneme 的运行数据保存在本机：

- 搜索索引数据库。
- 转写文本 JSON 文件。
- 本地模型缓存。
- 资料来源设置和 folder bookmarks。
- 用户启用 Activity Log 写回后生成的 daily-note 内容。

macOS 版本使用用户的 Application Support 文件夹。Windows Desktop 默认使用 `%APPDATA%\Mneme`，backend 开发时也可通过 `MNEME_WINDOWS_DATA_DIR` 或 `--data-dir` 改到测试目录。

Mneme 不包含云同步、云端推理、分析统计或遥测。

## 本地 Agent 接口

App bundle 内包含无界面的 `mneme` 命令：

```bash
/Applications/Mneme.app/Contents/Helpers/mneme
```

常用命令：

```bash
mneme doctor --json
mneme search "query" --json
mneme answer "question" --json
mneme remember "short memory text" --tags research,agent --json
mneme mcp
```

给 MCP client 注册时使用同一个可执行文件，并设置 `args: ["mcp"]`。能调用该 MCP server 的 agent 可以读取已索引的本地语料，所以只应授权给你信任的 agent。

## 主要功能

- 菜单栏应用，包含主窗口和快速搜索面板。
- 本地索引笔记、PDF、代码、转写文本和活动日志。
- 本地索引受管记忆、已选择的 agent 日志、Zotero 元数据和网页剪藏。
- 使用 CoreML multilingual embeddings 的本地语义搜索。
- 混合检索结合本地语义向量、FTS5 关键词检索和中文 bigram 匹配。
- 使用 MLX 的本地带引用问答，并保留本地 fallback 回答路径。
- `mneme` CLI/MCP agent 接口：`search`、`answer`、`sources`、`remember`、`doctor` 和 `mcp`。
- WhisperKit 本地音频转写、转写索引、Obsidian 导出和时间戳播放。
- Activity Log 支持 workspace 文件变化和 git 活动，可选本地每日摘要。
- 支持资料文件夹监听、全局快捷键配置和登录时启动。
- Windows Desktop 包含原生窗口、托盘入口、`Ctrl+Space` 全局快捷键、原生文件夹选择器、Sources、Search / Ask、Transcripts、Activity 和 Settings，支持本地来源扫描与带引用的摘录式问答。

## 当前版本

v0.1.0 是第一个公开 macOS 版本，适合本地测试和早期日常使用。当前仍有以下实际限制：

- 超大规模科研资料库仍需要更多验证。
- 长录音可能需要较长处理时间和本地磁盘空间。
- 混合语言录音和扫描 PDF 建议用用户自己的代表性文件检查效果。
- 可选本地模型可能在首次使用时下载，并依赖首次配置时的网络状态。
- Windows 现在有 Desktop packaging path，可由 CI 产出 installer artifact。它支持本地文件夹索引、搜索、摘录式 Ask 回答、转写文本导入、activity scan、原生 tray/window shell、原生文件夹选择器和 `Ctrl+Space` 全局快捷键。CoreML e5、MLX 生成、WhisperKit 音频转写和完整 PDF 文本抽取仍是 macOS-only 或后续 Windows runtime 工作。

未发布的 Windows Desktop 记录见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。

## 开源协议

Mneme 使用 [MIT License](LICENSE) 开源。
