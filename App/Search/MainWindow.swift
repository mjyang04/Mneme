import AppKit
import MnemeCore
import SwiftUI

struct MainWindow: View {
    var body: some View {
        TabView {
            SearchTab()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            ActivityView()
                .tabItem {
                    Label("Activity", systemImage: "calendar")
                }

            TranscriptsView()
                .tabItem {
                    Label("Transcripts", systemImage: "waveform")
                }

            SettingsView()
                .tabItem {
                    Label("Sources", systemImage: "folder")
                }
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

private struct SearchTab: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.mode) {
                    ForEach(SearchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                TextField(viewModel.mode == .ask ? "问我的文件..." : "搜索我的文件...", text: $viewModel.queryText)
                    .textFieldStyle(.plain)
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(10)

            Divider()

            if viewModel.mode == .ask, let answer = viewModel.answer {
                RagAnswerView(answer: answer)
            } else if viewModel.hits.isEmpty {
                ContentUnavailableView(
                    "无结果",
                    systemImage: "magnifyingglass",
                    description: Text("先在设置里添加来源并重建索引,然后输入关键词或问题。")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(viewModel.hits, id: \.chunkId) { hit in
                    ResultRow(hit: hit)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            ResultOpener.open(hit)
                        }
                }
            }
        }
        .onAppear {
            viewModel.attach(env.query)
        }
        .task(id: viewModel.queryText) {
            await viewModel.search(viewModel.queryText)
        }
        .task(id: viewModel.mode) {
            await viewModel.search(viewModel.queryText)
        }
    }
}

private struct RagAnswerView: View {
    let answer: RagAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(answer.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }

            Divider()

            if answer.citations.isEmpty {
                Text("没有可点击引用。")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(Array(answer.citations.enumerated()), id: \.element.chunkId) { index, hit in
                    HStack(alignment: .top, spacing: 8) {
                        Text("[\(index + 1)]")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                            ResultRow(hit: hit)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    ResultOpener.open(hit)
                                }
                        }
                    }
                .frame(minHeight: 180)
            }
        }
    }
}
