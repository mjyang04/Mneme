import XCTest
@testable import MnemeCore

final class HotKeyPreferencesTests: XCTestCase {
    func test_defaultQuickSearchHotKeyIsOptionSpace() {
        let descriptor = HotKeyDescriptor.defaultQuickSearch

        XCTAssertEqual(descriptor.keyCode, 49)
        XCTAssertEqual(descriptor.modifiers, [.option])
        XCTAssertEqual(descriptor.displayName, "Option+Space")
        XCTAssertTrue(descriptor.isValid)
    }

    func test_saveAndLoadQuickSearchHotKeyRoundTrips() {
        let suiteName = "MnemeCoreTests.HotKeyPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = HotKeyPreferences(defaults: defaults)
        let descriptor = HotKeyDescriptor(keyCode: 12, modifiers: [.command, .shift])

        preferences.saveQuickSearchHotKey(descriptor)

        XCTAssertEqual(preferences.loadQuickSearchHotKey(), descriptor)
    }

    func test_loadQuickSearchHotKeyFallsBackToDefaultWhenStoredValueIsInvalid() {
        let suiteName = "MnemeCoreTests.HotKeyPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = HotKeyPreferences(defaults: defaults)

        preferences.saveQuickSearchHotKey(HotKeyDescriptor(keyCode: 12, modifiers: []))

        XCTAssertEqual(preferences.loadQuickSearchHotKey(), .defaultQuickSearch)
    }

    func test_displayNameUsesReadableModifiersAndKey() {
        let descriptor = HotKeyDescriptor(keyCode: 8, modifiers: [.command, .option, .control])

        XCTAssertEqual(descriptor.displayName, "Command+Option+Control+C")
    }
}
