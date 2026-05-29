# Mneme — 本地科研第二大脑 (working name)

一个**完全离线**、常驻菜单栏的 macOS app:把你的笔记、论文 PDF、代码、语音转写、活动日志统一索引在本机,随时按全局热键唤起「问我的文件」。**数据永不出本机。**

> Working name「Mneme」(记忆女神)仅占位,可随时改;改名只需重命名本文件夹 + 更新文档标题。

## 为什么做它

研究者每天都犯「我知道我见过、但翻不到」的毛病:笔记在 Obsidian、论文在 PDF 文件夹、代码在各仓库、灵感在语音备忘里。Mneme 用**本地语义检索**把这些统一起来,完全在 Apple Silicon 上跑,隐私零外泄。

## 产品形态

- 常驻**菜单栏**(MenuBarExtra)
- **全局热键**唤起 Spotlight 式快搜悬浮窗(NSPanel)
- **主窗口**:搜索 / 转写 / 活动日志 / 来源与设置

## 三个模块(统一产品,共享索引)

| 模块 | 角色 | 内容 |
|---|---|---|
| ① Index & Query | 地基 / 查询层 | 笔记+PDF+代码 → 语义搜索;phase2 本地 LLM RAG 问答 |
| ② Transcription | 内容来源 | WhisperKit 本地语音转写 → 汇入索引 + 导出 Obsidian |
| ③ Activity Log | 内容来源 | FSEvents+git 捕获每日活动 → 写进 Obsidian 日记 |

## 技术栈(全部本地)

Swift / SwiftUI · CoreML(embedding,走 ANE)· MLX-swift(本地 LLM)· WhisperKit(转写)· GRDB(SQLite + BLOB 向量检索;sqlite-vec 可后续替换)· PDFKit + Vision(PDF/OCR)· FSEvents(文件监听)。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/00-product-design.md](docs/00-product-design.md) | 产品总体设计:架构、选型、数据模型、隐私、测试、建造分期 |
| [docs/01-module-index-query.md](docs/01-module-index-query.md) | 模块① spec:连接器 / 分块 / embedding / 索引 / 语义搜索 / RAG |
| [docs/02-module-transcription.md](docs/02-module-transcription.md) | 模块② spec:WhisperKit 转写 / 归档 / 导出 |
| [docs/03-module-activity-log.md](docs/03-module-activity-log.md) | 模块③ spec:活动捕获 / 每日日志 / Obsidian 写回 |

## 当前状态

**v0.1.0 本地可运行实现阶段**。仓库现在包含 SwiftPM package、`MnemeCore`、SwiftUI 菜单栏 app、测试套件和本地 `.app` 打包脚本。

已实现:
- 菜单栏 app、主窗口、快搜悬浮窗和可配置全局热键。
- Notes / PDF / Code / Transcript / Activity 连接器。
- GRDB-backed 本地索引、增量 indexing、语义搜索、MLX 本地 RAG streaming 生成和带引用的 extractive fallback。
- Search/QuickSearch 结果可打开原文;笔记命中优先走 Obsidian URI,失败再回退系统打开。
- CoreML multilingual-e5:已转换本地 `.mlpackage` 和 tokenizer 资产,打包进 `.build/Mneme.app`;资源缺失时回退到 NLEmbedding/Hashing。
- Activity Log: 手动刷新、运行期 FSEvents 监听、git 活动收集、可选 MLX 每日摘要、Obsidian daily note 受管段落写回。
- Transcripts: WhisperKit 音频转写、导入已有文本、语音备忘文件夹监听、JSON 持久化、索引、Obsidian 导出、时间戳段落播放。
- Sources: 文件夹选择保存 security-scoped bookmark;可启动来源 FSEvents 监听,变化后去抖自动重建索引。
- Settings: 可配置快搜热键和登录时启动。
- 本地打包: `scripts/build_app_bundle.sh` 生成 `.build/Mneme.app`,复制 e5 资产、SwiftPM 资源 bundle 和 MLX `mlx.metallib`。

当前主要限制:真实用户语料规模、长音频性能、混合语言录音质量、更多真实扫描 PDF OCR 样本和更大 MLX 模型选择仍需要继续验证。

常用命令:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/build_app_bundle.sh
```

重新生成 e5 资产:

```bash
uv run --with transformers --with torch --with coremltools \
  scripts/convert_e5_to_coreml.py --output-dir .build/Models/e5
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/build_app_bundle.sh
```

e5 bundle 诊断:

```bash
MNEME_DIAGNOSTIC=1 .build/Mneme.app/Contents/MacOS/Mneme
```

WhisperKit 转写诊断:

```bash
MNEME_TRANSCRIBE_DIAGNOSTIC_AUDIO=/path/to/audio.wav \
  MNEME_TRANSCRIBE_DIAGNOSTIC_MODEL=tiny \
  MNEME_TRANSCRIBE_DIAGNOSTIC_LANGUAGE=en \
  .build/Mneme.app/Contents/MacOS/Mneme
```

MLX RAG 诊断:

```bash
MNEME_MLX_DIAGNOSTIC=1 .build/Mneme.app/Contents/MacOS/Mneme
```

Activity MLX 摘要诊断:

```bash
MNEME_ACTIVITY_SUMMARY_DIAGNOSTIC=1 .build/Mneme.app/Contents/MacOS/Mneme
```

MLX 命令行/app bundle 需要 `mlx.metallib`;`scripts/build_app_bundle.sh` 会自动调用 `scripts/build_mlx_metallib.sh`。如果本机缺 Metal Toolchain,先运行:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -downloadComponent MetalToolchain
```

## 目标环境

Apple Silicon(开发机 M5 Pro)· macOS 14+ · 内容中英混合。

## License

MIT. See [LICENSE](LICENSE).
