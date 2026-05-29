import AppKit
import MnemeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var hotKey = HotKeyPreferences().loadQuickSearchHotKey()
    @State private var hotKeyStatus = ""
    @State private var sourceWatchStatus = ""
    @State private var launchAtLogin = LoginItemController.isEnabled
    @State private var loginItemStatus = ""
    private let hotKeyPreferences = HotKeyPreferences()

    var body: some View {
        Form {
            Section("来源文件夹") {
                if env.sources.sources.isEmpty {
                    Text("尚未添加来源")
                        .foregroundStyle(.secondary)
                }

                ForEach(env.sources.sources) { source in
                    HStack {
                        Text(source.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .leading)
                        Text(source.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            env.sources.remove(source.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    Button("添加笔记夹") { addFolder(.notes) }
                    Button("添加论文夹") { addFolder(.pdf) }
                    Button("添加代码仓") { addFolder(.code) }
                }
            }

            Section("索引") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(env.isIndexing ? "索引中..." : "重建索引") {
                            Task { await env.reindex() }
                        }
                        .disabled(env.isIndexing)

                        Button(env.sourceWatcher.isWatching ? "停止来源监听" : "启动来源监听") {
                            toggleSourceWatching()
                        }
                        .disabled(env.sources.sources.isEmpty)

                        Text(env.sourceWatcher.isWatching ? "监听中" : "未监听")
                            .font(.caption)
                            .foregroundStyle(env.sourceWatcher.isWatching ? .green : .secondary)
                    }

                    Text(env.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !sourceWatchStatus.isEmpty {
                        Text(sourceWatchStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("启动") {
                Toggle("登录时启动 Mneme", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if !loginItemStatus.isEmpty {
                    Text(loginItemStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("快搜热键") {
                Picker("按键", selection: Binding(
                    get: { hotKey.keyCode },
                    set: { hotKey = HotKeyDescriptor(keyCode: $0, modifiers: hotKey.modifiers) }
                )) {
                    ForEach(HotKeyKey.common) { key in
                        Text(key.displayName).tag(key.keyCode)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Toggle("Command", isOn: modifierBinding(.command))
                    Toggle("Option", isOn: modifierBinding(.option))
                    Toggle("Control", isOn: modifierBinding(.control))
                    Toggle("Shift", isOn: modifierBinding(.shift))
                }

                HStack {
                    Text(hotKey.isValid ? hotKey.displayName : "至少选择一个修饰键")
                        .font(.caption)
                        .foregroundColor(hotKey.isValid ? .secondary : .red)
                    Spacer()
                    Button("恢复默认") {
                        hotKey = .defaultQuickSearch
                        saveHotKey()
                    }
                    Button("保存热键") {
                        saveHotKey()
                    }
                    .disabled(!hotKey.isValid)
                }

                if !hotKeyStatus.isEmpty {
                    Text(hotKeyStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("当前限制") {
                Text("快搜热键和登录项可在本页修改；来源文件夹支持运行期 FSEvents 监听并自动重建索引；WhisperKit 可转写音频并汇入索引；MLX 可流式生成带引用回答并保留 extractive fallback；活动日志支持手动刷新、运行期后台监听和可选 MLX 摘要；本地 .app 可由脚本生成。仍需继续验证真实用户语料、长音频性能、混合语言录音质量、扫描 PDF OCR 样本和更大 MLX 模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 560)
    }

    private func addFolder(_ kind: SourceKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            env.sources.add(kind: kind, url: url)
        }
    }

    private func toggleSourceWatching() {
        if env.sourceWatcher.isWatching {
            env.stopSourceWatching()
            sourceWatchStatus = "已停止来源监听"
        } else {
            env.startSourceWatching()
            sourceWatchStatus = env.sourceWatcher.isWatching ? "来源变化会在去抖后自动重建索引" : "来源监听启动失败"
        }
    }

    private func modifierBinding(_ modifier: HotKeyModifiers) -> Binding<Bool> {
        Binding {
            hotKey.modifiers.contains(modifier)
        } set: { isEnabled in
            var modifiers = hotKey.modifiers
            if isEnabled {
                modifiers.insert(modifier)
            } else {
                modifiers.remove(modifier)
            }
            hotKey = HotKeyDescriptor(keyCode: hotKey.keyCode, modifiers: modifiers)
        }
    }

    private func saveHotKey() {
        guard hotKey.isValid else { return }
        hotKeyPreferences.saveQuickSearchHotKey(hotKey)
        if GlobalHotKeyController.shared.registerQuickSearchHotKey(hotKey) {
            hotKeyStatus = "已保存: \(hotKey.displayName)"
        } else {
            hotKeyStatus = "注册失败: \(hotKey.displayName) 可能已被其他 app 占用"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemController.setEnabled(enabled)
            launchAtLogin = LoginItemController.isEnabled
            loginItemStatus = launchAtLogin ? "已启用登录时启动" : "已关闭登录时启动"
        } catch {
            launchAtLogin = LoginItemController.isEnabled
            loginItemStatus = "登录项设置失败: \(error.localizedDescription)"
        }
    }
}
