import Foundation

public final class HotKeyPreferences: @unchecked Sendable {
    private enum Keys {
        static let keyCode = "quickSearchHotKey.keyCode"
        static let modifiers = "quickSearchHotKey.modifiers"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadQuickSearchHotKey() -> HotKeyDescriptor {
        guard defaults.object(forKey: Keys.keyCode) != nil,
              defaults.object(forKey: Keys.modifiers) != nil else {
            return .defaultQuickSearch
        }

        let descriptor = HotKeyDescriptor(
            keyCode: UInt32(defaults.integer(forKey: Keys.keyCode)),
            modifiers: HotKeyModifiers(rawValue: UInt32(defaults.integer(forKey: Keys.modifiers)))
        )
        return descriptor.isValid ? descriptor : .defaultQuickSearch
    }

    public func saveQuickSearchHotKey(_ descriptor: HotKeyDescriptor) {
        defaults.set(Int(descriptor.keyCode), forKey: Keys.keyCode)
        defaults.set(Int(descriptor.modifiers.rawValue), forKey: Keys.modifiers)
    }
}
