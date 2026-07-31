import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: Error, Equatable {
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)
}

final class GlobalHotKey {
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey)

    private static let signature: OSType = 0x5350_4153 // "SPAS"

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (@Sendable () -> Void)?

    deinit {
        unregister()
    }

    func register(
        keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
        modifiers: UInt32 = GlobalHotKey.defaultModifiers,
        action: @escaping @Sendable () -> Void
    ) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.eventHandlerProc,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            self.action = nil
            throw GlobalHotKeyError.eventHandlerRegistrationFailed(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr else {
            unregister()
            throw GlobalHotKeyError.hotKeyRegistrationFailed(registrationStatus)
        }
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        action = nil
    }

    private static let eventHandlerProc: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        hotKey.action?()
        return noErr
    }
}
