import Foundation

enum ModelDownloadSettings {
    static let mlxDownloadKey = "mneme.models.mlxDownloadEnabled.v1"

    static var allowsMLXModelDownload: Bool {
        get {
            UserDefaults.standard.bool(forKey: mlxDownloadKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: mlxDownloadKey)
        }
    }
}
