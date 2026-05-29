import Carbon
import Foundation
import MnemeCore

@MainActor
final class GlobalHotKeyController {
    static let shared = GlobalHotKeyController()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: GlobalHotKeyController.signature, id: 1)

    private init() {}

    @discardableResult
    func registerQuickSearchHotKey(_ descriptor: HotKeyDescriptor) -> Bool {
        guard descriptor.isValid else { return false }
        installEventHandlerIfNeeded()
        unregisterHotKey()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            hotKeyRef = ref
            return true
        }
        return false
    }

    func registerDefaultQuickSearchHotKey() {
        registerQuickSearchHotKey(.defaultQuickSearch)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var eventHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )
                guard status == noErr,
                      eventHotKeyID.signature == GlobalHotKeyController.signature,
                      eventHotKeyID.id == 1 else {
                    return noErr
                }

                Task { @MainActor in
                    QuickSearchController.shared.toggle()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        eventHandlerRef = handlerRef
    }

    private static let signature: OSType = {
        var result: OSType = 0
        for scalar in "MNEM".unicodeScalars {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }()
}
