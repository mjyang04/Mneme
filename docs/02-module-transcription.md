# 模块② — Transcription(语音转写)

- 状态:Design / 待评审
- 依赖:模块①(转写稿经 `TranscriptConnector` 汇入索引)
- 对应建造期:P4

macOS 用 WhisperKit 在本机把会议 / 语音备忘 / 讲座录音转写,自动归档、可检索、可导出 Obsidian。Windows Desktop 当前只支持 transcript text import,先落地转写稿管理和索引路径。

---

## 1. 范围

**包含**
- 音频输入:拖拽音频文件、监听一个「语音备忘文件夹」、可选麦克风现场录音。
- macOS:WhisperKit 本地转写(多语、带段级时间戳)。
- Windows Desktop:粘贴或导入 transcript text,经同一信息结构进入索引。
- 转写稿持久化 + 经 `TranscriptConnector` 汇入模块①索引。
- 转写管理 UI(列表 / 详情 / 时间轴 / 站内搜索)。
- 导出为 Obsidian `.md`(frontmatter + 时间戳分段)。

**不包含**
- 说话人分离(diarization)——本版不做,列为后续。
- 实时字幕 / 会议机器人接入——不做。
- Windows audio transcription runtime——当前 Desktop build 不做,后续需选择 Whisper.cpp、ONNX Runtime 或其它本地 Windows 方案。

---

## 2. 输入来源

| 输入 | 说明 |
|---|---|
| 拖拽文件 | 主窗口转写页拖入 `.m4a/.mp3/.wav/.mov` 等;入队转写 |
| 文件夹监听 | 指定「语音备忘」文件夹,FSEvents 检测新文件自动入队(复用模块③的监听基建) |
| 麦克风录音 | 可选:`AVAudioEngine` 录音 → 落盘 → 转写(v1 可后置) |

---

## 3. WhisperKit 集成

本节是 macOS 正式实现路径。Windows Desktop 不加载 WhisperKit。

```swift
protocol TranscriptionService {
    func transcribe(_ audio: URL,
                    options: TranscribeOptions) -> AsyncStream<TranscriptSegment>
}

struct TranscribeOptions {
    var modelSize: WhisperModel = .largeV3Turbo   // tiny/base/small/largeV3Turbo
    var language: String? = nil                    // nil = 自动检测
}

struct TranscriptSegment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}
```

- 模型默认 `large-v3-turbo`(M5 Pro 上速度/质量平衡好);低配可切 `small`。
- 多语:`language=nil` 自动检测,支持中英及其他。
- 长音频:WhisperKit 内部分窗;UI 显示进度(已转写时长 / 总时长)。
- 段级时间戳进 `locator`,使「点击转写片段 → 跳到音频时间点」成为可能。

---

## 4. 持久化与索引

- 一段录音 = 一个 `document`(`kind = .transcript`);`meta` 存:音频文件 uri、时长、语言、模型、转写时间。
- 转写全文按段聚合后交给模块①的 `Chunker`(时间戳作为 locator),`EmbeddingService` 向量化,`IndexStore` 入库。
- 于是转写稿天然出现在全局搜索结果里(来源 icon 标为「转写」)。

---

## 5. 导出 Obsidian

- 写到用户指定的「转写笔记」文件夹:`Transcripts/{date}-{slug}.md`。
- 格式:
  ```markdown
  ---
  type: transcript
  source_audio: "voice-memo-2026-05-29.m4a"
  duration: "12:34"
  language: zh
  model: large-v3-turbo
  created: 2026-05-29
  ---

  - [00:00] 开场…
  - [00:12] …
  ```
- 已存在则按受管段落规则更新,不覆盖用户后加的批注。

---

## 6. UI

- 转写页:左列转写列表(标题 / 日期 / 时长 / 语言 / 状态:排队/转写中/完成/失败);右侧详情。
- 详情:可滚动的时间戳分段文本;顶部播放条(点击段落跳时间点);站内关键词搜索。
- 操作:重转(换模型/语言)、导出 Obsidian、在 Finder 显示音频、删除。

---

## 7. 错误处理

| 场景 | 处理 |
|---|---|
| 音频损坏 / 不支持格式 | 标记该条「失败」+ 原因;可重试 |
| 超长音频内存压力 | 依赖 WhisperKit 分窗;必要时限制并发为 1 |
| 模型未下载 | 首次使用引导下载;失败给明确提示,不静默 |
| 转写中断/退出 | 已完成的段落落盘;重启后可从断点续转或整段重转 |

---

## 8. 验收标准

- [ ] 拖入一段中英混合录音能完成转写,带段级时间戳。
- [ ] 转写完成后,其内容能在全局热键搜索里被检索到。
- [ ] 导出的 Obsidian md 含 frontmatter + 时间戳分段,二次导出不覆盖用户批注。
- [ ] 点击某段能跳到音频对应时间点播放。
- [ ] 转写全程离线,无网络请求(模型已就绪时)。
- [ ] Windows Desktop 能 import transcript text、重建 index,并在 Search / Ask 中命中该 transcript。

---

## 9. 风险

- 转写准确率受口音/噪声影响 → 提供换更大模型重转。
- 大模型首次加载慢 / 占内存 → `ModelManager` 在空闲时卸载,按需加载。
- 与模块①共享 Chunker/Embedding 的前缀约定要一致(转写稿按 passage 处理)。
