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

Swift / SwiftUI · CoreML(embedding,走 ANE)· MLX-swift(可选本地 LLM)· WhisperKit(转写)· GRDB + sqlite-vec(向量库)· PDFKit + Vision(PDF/OCR)· FSEvents(文件监听)。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/00-product-design.md](docs/00-product-design.md) | 产品总体设计:架构、选型、数据模型、隐私、测试、建造分期 |
| [docs/01-module-index-query.md](docs/01-module-index-query.md) | 模块① spec:连接器 / 分块 / embedding / 索引 / 语义搜索 / RAG |
| [docs/02-module-transcription.md](docs/02-module-transcription.md) | 模块② spec:WhisperKit 转写 / 归档 / 导出 |
| [docs/03-module-activity-log.md](docs/03-module-activity-log.md) | 模块③ spec:活动捕获 / 每日日志 / Obsidian 写回 |

## 当前状态

**设计阶段**。本仓库目前只含开发文档。代码尚未开始;实现计划将由 `superpowers:writing-plans` 在文档 review 通过后生成。

## 目标环境

Apple Silicon(开发机 M5 Pro)· macOS 14+ · 内容中英混合。
