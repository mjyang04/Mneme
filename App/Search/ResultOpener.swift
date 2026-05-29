import AppKit
import Foundation
import MnemeCore

enum ResultOpener {
    static func open(_ hit: SearchHit) {
        if hit.kind == .notes, hit.uri.isFileURL, openInObsidian(hit.uri) {
            return
        }
        NSWorkspace.shared.open(hit.uri)
    }

    private static func openInObsidian(_ fileURL: URL) -> Bool {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.path)
        ]
        guard let url = components.url else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
