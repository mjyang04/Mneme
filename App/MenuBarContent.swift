import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain")
                Text("Mneme").font(.headline)
            }

            Text(env.statusMessage.isEmpty ? "就绪" : env.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                openWindow(id: "main")
            } label: {
                Label("打开主窗口", systemImage: "rectangle")
            }

            Button {
                QuickSearchController.shared.toggle()
            } label: {
                Label("快搜", systemImage: "magnifyingglass")
            }

            Button {
                Task { await env.reindex() }
            } label: {
                Label(env.isIndexing ? "索引中..." : "重建索引", systemImage: "arrow.clockwise")
            }
            .disabled(env.isIndexing)

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "xmark.circle")
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
