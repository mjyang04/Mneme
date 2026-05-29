import Foundation

public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 8)
    public static let shift = HotKeyModifiers(rawValue: 1 << 9)
    public static let option = HotKeyModifiers(rawValue: 1 << 11)
    public static let control = HotKeyModifiers(rawValue: 1 << 12)

    static let orderedDisplayParts: [(modifier: HotKeyModifiers, name: String)] = [
        (.command, "Command"),
        (.option, "Option"),
        (.control, "Control"),
        (.shift, "Shift")
    ]
}

public struct HotKeyKey: Hashable, Identifiable, Sendable {
    public let keyCode: UInt32
    public let displayName: String

    public var id: UInt32 { keyCode }

    public init(keyCode: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.displayName = displayName
    }

    public static let common: [HotKeyKey] = [
        HotKeyKey(keyCode: 49, displayName: "Space"),
        HotKeyKey(keyCode: 36, displayName: "Return"),
        HotKeyKey(keyCode: 48, displayName: "Tab"),
        HotKeyKey(keyCode: 0, displayName: "A"),
        HotKeyKey(keyCode: 11, displayName: "B"),
        HotKeyKey(keyCode: 8, displayName: "C"),
        HotKeyKey(keyCode: 2, displayName: "D"),
        HotKeyKey(keyCode: 14, displayName: "E"),
        HotKeyKey(keyCode: 3, displayName: "F"),
        HotKeyKey(keyCode: 5, displayName: "G"),
        HotKeyKey(keyCode: 4, displayName: "H"),
        HotKeyKey(keyCode: 34, displayName: "I"),
        HotKeyKey(keyCode: 38, displayName: "J"),
        HotKeyKey(keyCode: 40, displayName: "K"),
        HotKeyKey(keyCode: 37, displayName: "L"),
        HotKeyKey(keyCode: 46, displayName: "M"),
        HotKeyKey(keyCode: 45, displayName: "N"),
        HotKeyKey(keyCode: 31, displayName: "O"),
        HotKeyKey(keyCode: 35, displayName: "P"),
        HotKeyKey(keyCode: 12, displayName: "Q"),
        HotKeyKey(keyCode: 15, displayName: "R"),
        HotKeyKey(keyCode: 1, displayName: "S"),
        HotKeyKey(keyCode: 17, displayName: "T"),
        HotKeyKey(keyCode: 32, displayName: "U"),
        HotKeyKey(keyCode: 9, displayName: "V"),
        HotKeyKey(keyCode: 13, displayName: "W"),
        HotKeyKey(keyCode: 7, displayName: "X"),
        HotKeyKey(keyCode: 16, displayName: "Y"),
        HotKeyKey(keyCode: 6, displayName: "Z"),
        HotKeyKey(keyCode: 29, displayName: "0"),
        HotKeyKey(keyCode: 18, displayName: "1"),
        HotKeyKey(keyCode: 19, displayName: "2"),
        HotKeyKey(keyCode: 20, displayName: "3"),
        HotKeyKey(keyCode: 21, displayName: "4"),
        HotKeyKey(keyCode: 23, displayName: "5"),
        HotKeyKey(keyCode: 22, displayName: "6"),
        HotKeyKey(keyCode: 26, displayName: "7"),
        HotKeyKey(keyCode: 28, displayName: "8"),
        HotKeyKey(keyCode: 25, displayName: "9")
    ]

    public static func displayName(for keyCode: UInt32) -> String? {
        common.first { $0.keyCode == keyCode }?.displayName
    }
}

public struct HotKeyDescriptor: Codable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers

    public init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultQuickSearch = HotKeyDescriptor(keyCode: 49, modifiers: [.option])

    public var isValid: Bool {
        !modifiers.isEmpty && HotKeyKey.displayName(for: keyCode) != nil
    }

    public var displayName: String {
        let modifierNames = HotKeyModifiers.orderedDisplayParts.compactMap { part in
            modifiers.contains(part.modifier) ? part.name : nil
        }
        let keyName = HotKeyKey.displayName(for: keyCode) ?? "Key \(keyCode)"
        return (modifierNames + [keyName]).joined(separator: "+")
    }
}
