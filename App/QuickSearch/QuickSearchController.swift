import AppKit
import MnemeCore
import SwiftUI

@MainActor
final class QuickSearchController {
    static let shared = QuickSearchController()

    private var panel: NSPanel?
    private var query: QueryService?

    func configure(query: QueryService) {
        self.query = query
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }

        guard let query else { return }
        let panel = panel ?? makePanel(query: query)
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel(query: QueryService) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: QuickSearchView(query: query) { [weak self] in
                self?.panel?.orderOut(nil)
            }
        )
        return panel
    }
}
