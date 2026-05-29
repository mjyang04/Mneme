import Foundation

@MainActor
final class TranscriptionSettingsStore: ObservableObject {
    @Published private(set) var watchedAudioFolderPath: String?

    private let watchedAudioFolderKey = "mneme.transcription.watchedAudioFolder.v1"

    init() {
        load()
    }

    var watchedAudioFolderURL: URL? {
        watchedAudioFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func setWatchedAudioFolder(_ path: String) {
        watchedAudioFolderPath = path
        save()
    }

    private func load() {
        watchedAudioFolderPath = UserDefaults.standard.string(forKey: watchedAudioFolderKey)
    }

    private func save() {
        UserDefaults.standard.set(watchedAudioFolderPath, forKey: watchedAudioFolderKey)
    }
}
