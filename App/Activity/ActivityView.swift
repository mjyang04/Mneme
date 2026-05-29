import AppKit
import MnemeCore
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var settings = ActivitySettingsStore()
    @StateObject private var watcher = ActivityFolderWatcher()
    @State private var isRefreshing = false
    @State private var status = ""
    @State private var preview = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("工作文件夹") {
                    if settings.workspacePaths.isEmpty {
                        Text("尚未添加工作文件夹")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(settings.workspacePaths, id: \.self) { path in
                        HStack {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                settings.removeWorkspace(path: path)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button("添加工作文件夹") {
                        chooseDirectory { settings.addWorkspace(path: $0) }
                    }
                }

                Section("Obsidian Daily 目录") {
                    HStack {
                        Text(settings.dailyNotesPath ?? "尚未选择")
                            .foregroundStyle(settings.dailyNotesPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("选择目录") {
                            chooseDirectory { settings.setDailyNotesPath($0) }
                        }
                    }
                }

                Section("刷新") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("启用 MLX 每日摘要", isOn: Binding(
                            get: { settings.llmSummaryEnabled },
                            set: { settings.setLLMSummaryEnabled($0) }
                        ))
                        .toggleStyle(.checkbox)

                        HStack {
                            Button(isRefreshing ? "刷新中..." : "刷新今天") {
                                Task { await refreshToday(reason: "手动刷新") }
                            }
                            .disabled(isRefreshing || settings.workspacePaths.isEmpty || settings.dailyNotesPath == nil)

                            Button(watcher.isWatching ? "停止后台监听" : "启动后台监听") {
                                toggleWatcher()
                            }
                            .disabled(settings.workspacePaths.isEmpty || settings.dailyNotesPath == nil)

                            Text(watcher.isWatching ? "监听中" : "未监听")
                                .font(.caption)
                                .foregroundStyle(watcher.isWatching ? .green : .secondary)
                        }

                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            ScrollView {
                Text(preview.isEmpty ? "刷新后这里显示生成的 Mneme 活动段落。" : preview)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160)
        }
        .onDisappear {
            watcher.stop()
        }
    }

    private func toggleWatcher() {
        if watcher.isWatching {
            watcher.stop()
            status = "后台监听已停止"
            return
        }

        watcher.start(workspaceURLs: settings.workspaceURLs) {
            await refreshToday(reason: "后台监听刷新")
        }
        status = watcher.isWatching ? "后台监听已启动" : "后台监听启动失败"
    }

    private func refreshToday(reason: String) async {
        guard let dailyNotesURL = settings.dailyNotesURL else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let calendar = Calendar.current
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            let day = Self.dayFormatter.string(from: now)
            let gitRepositories = settings.workspaceURLs.filter {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent(".git").path)
            }
            let service = ActivityLogService(
                workspaceRoots: settings.workspaceURLs,
                gitRepositories: gitRepositories,
                dailyNotesDirectory: dailyNotesURL
            )
            let result = try service.refresh(day: day, since: startOfDay)
            env.sources.add(kind: .activity, path: dailyNotesURL.path)
            let activity = try await activityWithOptionalSummary(result.activity, dailyNotesURL: dailyNotesURL)
            preview = DailyActivityRenderer().render(activity)
            status = "\(reason): 已写入 \(result.noteURL.lastPathComponent), 项目 \(activity.projects.count) 个"
            await env.reindex()
        } catch {
            status = "刷新失败: \(error.localizedDescription)"
        }
    }

    private func activityWithOptionalSummary(_ activity: DailyActivity, dailyNotesURL: URL) async throws -> DailyActivity {
        guard settings.llmSummaryEnabled else {
            return activity
        }

        status = "生成 MLX 活动摘要..."
        let summary = try await env.activitySummaryGenerator.summarize(activity)
        let summarized = DailyActivity(day: activity.day, projects: activity.projects, summary: summary)
        _ = try DailyNoteWriter(dailyDirectory: dailyNotesURL)
            .writeManagedBlock(DailyActivityRenderer().render(summarized), day: activity.day)
        return summarized
    }

    private func chooseDirectory(_ onSelect: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let path = panel.url?.path {
            onSelect(path)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
