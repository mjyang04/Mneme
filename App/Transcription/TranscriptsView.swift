import AppKit
import AVFoundation
import MnemeCore
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var settings = TranscriptionSettingsStore()
    @StateObject private var audioFolderWatcher = SourceFolderWatcher()
    @State private var transcripts: [TranscriptDocument] = []
    @State private var selectedID: TranscriptDocument.ID?
    @State private var title = ""
    @State private var language = ""
    @State private var importedText = ""
    @State private var exportDirectory: String?
    @State private var status = ""
    @State private var audioURL: URL?
    @State private var audioTitle = ""
    @State private var audioModel = "large-v3-v20240930_626MB"
    @State private var allowModelDownload = false
    @State private var isTranscribing = false
    @State private var player: AVPlayer?

    private var selectedTranscript: TranscriptDocument? {
        transcripts.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcripts")
                    .font(.headline)
                List(transcripts, selection: $selectedID) { transcript in
                    VStack(alignment: .leading) {
                        Text(transcript.title)
                            .font(.body)
                        Text(transcript.createdAt.formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("刷新列表") { reload() }
            }
            .padding()
            .frame(minWidth: 240)

            VStack(alignment: .leading, spacing: 12) {
                GroupBox("导入已有转写文本") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("标题", text: $title)
                        TextField("语言，例如 zh / en", text: $language)
                        TextEditor(text: $importedText)
                            .font(.body)
                            .frame(minHeight: 120)
                            .border(Color.secondary.opacity(0.25))
                        HStack {
                            Button("导入并索引") {
                                Task { await importTranscript() }
                            }
                            .disabled(importedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("转写音频文件") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(audioURL?.lastPathComponent ?? "尚未选择音频")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("选择音频") { chooseAudioFile() }
                        }
                        TextField("标题，留空则使用文件名", text: $audioTitle)
                        HStack {
                            TextField("WhisperKit 模型", text: $audioModel)
                            Toggle("自动准备转写模型", isOn: $allowModelDownload)
                                .toggleStyle(.checkbox)
                        }
                        HStack {
                            Button(isTranscribing ? "转写中..." : "转写并索引") {
                                Task { await transcribeAudio() }
                            }
                            .disabled(audioURL == nil || isTranscribing || audioModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("模型目录: \(env.whisperModelDirectory().path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: acceptAudioDrop)

                GroupBox("语音备忘文件夹") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(settings.watchedAudioFolderPath ?? "尚未选择语音备忘文件夹")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("选择目录") { chooseWatchedAudioFolder() }
                        }
                        HStack {
                            Button(audioFolderWatcher.isWatching ? "停止监听" : "启动监听") {
                                toggleAudioFolderWatcher()
                            }
                            .disabled(settings.watchedAudioFolderURL == nil || isTranscribing)

                            Button("扫描新音频") {
                                Task { await transcribePendingAudioFiles(reason: "手动扫描") }
                            }
                            .disabled(settings.watchedAudioFolderURL == nil || isTranscribing)

                            Text(audioFolderWatcher.isWatching ? "监听中" : "未监听")
                                .font(.caption)
                                .foregroundStyle(audioFolderWatcher.isWatching ? .green : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("详情与导出") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let selectedTranscript {
                            Text(selectedTranscript.title)
                                .font(.headline)
                            if let audioPath = selectedTranscript.sourceAudioPath {
                                Text(audioPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(selectedTranscript.segments.enumerated()), id: \.offset) { _, segment in
                                        HStack(alignment: .top, spacing: 8) {
                                            Button(Self.timestamp(segment.start)) {
                                                play(selectedTranscript, at: segment.start)
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption.monospacedDigit())
                                            .disabled(selectedTranscript.sourceAudioPath == nil)
                                            Text(segment.text)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 140)
                            HStack {
                                Text(exportDirectory ?? "尚未选择导出目录")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Button("选择导出目录") { chooseExportDirectory() }
                                Button("导出 Obsidian") {
                                    export(selectedTranscript)
                                }
                                .disabled(exportDirectory == nil)
                            }
                        } else {
                            Text("选择一个转写稿查看详情。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .frame(minWidth: 460)
        }
        .onAppear { reload() }
        .onDisappear { audioFolderWatcher.stop() }
    }

    private func reload() {
        transcripts = (try? env.transcriptStore.list()) ?? []
        if selectedID == nil {
            selectedID = transcripts.first?.id
        }
    }

    private func importTranscript() async {
        do {
            let service = TranscriptImportService(store: env.transcriptStore)
            let transcript = try service.importPlainText(
                title: title,
                text: importedText,
                language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : language
            )
            env.sources.add(kind: .transcript, path: env.transcriptStoreDirectory().path)
            title = ""
            language = ""
            importedText = ""
            reload()
            selectedID = transcript.id
            status = "已导入 \(transcript.title)"
            await env.reindex()
        } catch {
            status = "导入失败: \(error.localizedDescription)"
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let path = panel.url?.path {
            exportDirectory = path
        }
    }

    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            setAudioURL(url)
        }
    }

    private func chooseWatchedAudioFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let path = panel.url?.path {
            settings.setWatchedAudioFolder(path)
        }
    }

    private func toggleAudioFolderWatcher() {
        if audioFolderWatcher.isWatching {
            audioFolderWatcher.stop()
            status = "语音备忘文件夹监听已停止"
            return
        }
        guard let folder = settings.watchedAudioFolderURL else { return }
        audioFolderWatcher.start(sourceURLs: [folder]) {
            await transcribePendingAudioFiles(reason: "文件夹监听")
        }
        status = audioFolderWatcher.isWatching ? "语音备忘文件夹监听已启动" : "语音备忘文件夹监听启动失败"
    }

    private func acceptAudioDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data,
                      let decoded = URL(dataRepresentation: data, relativeTo: nil) {
                url = decoded
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in
                setAudioURL(url)
            }
        }
        return true
    }

    private func setAudioURL(_ url: URL) {
        audioURL = url
        if audioTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            audioTitle = url.deletingPathExtension().lastPathComponent
        }
    }

    private func transcribeAudio() async {
        guard let audioURL else { return }
        isTranscribing = true
        status = "转写中: \(audioURL.lastPathComponent)"
        defer { isTranscribing = false }

        do {
            let service = TranscriptImportService(store: env.transcriptStore)
            let options = TranscribeOptions(
                model: audioModel.trimmingCharacters(in: .whitespacesAndNewlines),
                language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : language,
                allowsModelDownload: allowModelDownload
            )
            let transcript = try await service.importAudio(
                audio: audioURL,
                title: audioTitle,
                options: options,
                service: env.transcriptionService
            )
            env.sources.add(kind: .transcript, path: env.transcriptStoreDirectory().path)
            reload()
            selectedID = transcript.id
            status = "已转写 \(transcript.title)"
            await env.reindex()
        } catch {
            status = "转写失败: \(error.localizedDescription)"
        }
    }

    private func transcribePendingAudioFiles(reason: String) async {
        guard let folder = settings.watchedAudioFolderURL else { return }
        guard !isTranscribing else {
            status = "已有转写任务在运行"
            return
        }

        let pending = pendingAudioFiles(in: folder)
        guard !pending.isEmpty else {
            status = "\(reason): 没有新音频"
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let service = TranscriptImportService(store: env.transcriptStore)
        let options = TranscribeOptions(
            model: audioModel.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : language,
            allowsModelDownload: allowModelDownload
        )
        var imported: [TranscriptDocument] = []
        for audio in pending {
            do {
                status = "\(reason): 转写 \(audio.lastPathComponent)"
                let transcript = try await service.importAudio(
                    audio: audio,
                    title: audio.deletingPathExtension().lastPathComponent,
                    options: options,
                    service: env.transcriptionService
                )
                imported.append(transcript)
            } catch {
                status = "\(audio.lastPathComponent) 转写失败: \(error.localizedDescription)"
            }
        }

        if !imported.isEmpty {
            env.sources.add(kind: .transcript, path: env.transcriptStoreDirectory().path)
            reload()
            selectedID = imported.last?.id
            status = "\(reason): 已转写 \(imported.count) 个新音频"
            await env.reindex()
        }
    }

    private func pendingAudioFiles(in folder: URL) -> [URL] {
        let existingAudioPaths = Set(transcripts.compactMap(\.sourceAudioPath))
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                AudioFileSupport.supportedExtensions.contains(url.pathExtension.lowercased())
                    && !existingAudioPaths.contains(url.path)
            }
            .sorted { $0.path < $1.path }
    }

    private func export(_ transcript: TranscriptDocument) {
        guard let exportDirectory else { return }
        do {
            let exporter = TranscriptObsidianExporter(outputDirectory: URL(fileURLWithPath: exportDirectory, isDirectory: true))
            let url = try exporter.export(transcript)
            status = "已导出 \(url.lastPathComponent)"
        } catch {
            status = "导出失败: \(error.localizedDescription)"
        }
    }

    private func play(_ transcript: TranscriptDocument, at start: TimeInterval) {
        guard let path = transcript.sourceAudioPath else { return }
        let url = URL(fileURLWithPath: path)
        if player == nil || (player?.currentItem?.asset as? AVURLAsset)?.url != url {
            player = AVPlayer(url: url)
        }
        player?.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        player?.play()
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
