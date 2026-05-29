import Foundation

@MainActor
final class ActivitySettingsStore: ObservableObject {
    @Published private(set) var workspacePaths: [String] = []
    @Published private(set) var dailyNotesPath: String?
    @Published private(set) var llmSummaryEnabled = false

    private let workspaceKey = "mneme.activity.workspaces.v1"
    private let dailyNotesKey = "mneme.activity.dailyNotesPath.v1"
    private let llmSummaryKey = "mneme.activity.llmSummaryEnabled.v1"

    init() {
        load()
    }

    var workspaceURLs: [URL] {
        workspacePaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var dailyNotesURL: URL? {
        dailyNotesPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func addWorkspace(path: String) {
        guard !workspacePaths.contains(path) else { return }
        workspacePaths.append(path)
        save()
    }

    func removeWorkspace(path: String) {
        workspacePaths.removeAll { $0 == path }
        save()
    }

    func setDailyNotesPath(_ path: String) {
        dailyNotesPath = path
        save()
    }

    func setLLMSummaryEnabled(_ isEnabled: Bool) {
        llmSummaryEnabled = isEnabled
        save()
    }

    private func load() {
        workspacePaths = UserDefaults.standard.stringArray(forKey: workspaceKey) ?? []
        dailyNotesPath = UserDefaults.standard.string(forKey: dailyNotesKey)
        llmSummaryEnabled = UserDefaults.standard.bool(forKey: llmSummaryKey)
    }

    private func save() {
        UserDefaults.standard.set(workspacePaths, forKey: workspaceKey)
        UserDefaults.standard.set(dailyNotesPath, forKey: dailyNotesKey)
        UserDefaults.standard.set(llmSummaryEnabled, forKey: llmSummaryKey)
    }
}
