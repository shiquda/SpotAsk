import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: Error, Equatable {
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)
}

final class GlobalHotKey {
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey)

    static let signature: OSType = 0x5350_4153 // "SPAS"
    private let identifier: UInt32

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (@Sendable () -> Void)?

    init(identifier: UInt32 = 1) {
        self.identifier = identifier
    }

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

        let identifier = EventHotKeyID(signature: Self.signature, id: self.identifier)
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

    static func matchesEvent(signature: OSType, identifier: UInt32, expectedIdentifier: UInt32) -> Bool {
        signature == Self.signature && identifier == expectedIdentifier
    }

    static func configuration(for shortcut: InAppShortcut) -> (keyCode: UInt32, modifiers: UInt32)? {
        let keyCodes: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z), "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1),
            "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
            ",": UInt32(kVK_ANSI_Comma), ".": UInt32(kVK_ANSI_Period), "/": UInt32(kVK_ANSI_Slash),
            "-": UInt32(kVK_ANSI_Minus), "=": UInt32(kVK_ANSI_Equal),
            " ": UInt32(kVK_Space)
        ]
        guard let keyCode = keyCodes[shortcut.key] else { return nil }
        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        return (keyCode, modifiers)
    }

    private func handles(_ event: EventRef?) -> Bool {
        guard let event else { return false }
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
        return status == noErr && Self.matchesEvent(
            signature: eventHotKeyID.signature,
            identifier: eventHotKeyID.id,
            expectedIdentifier: identifier
        )
    }

    private static let eventHandlerProc: EventHandlerUPP = { _, event, userData in
        guard let userData else { return noErr }
        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        guard hotKey.handles(event) else { return OSStatus(eventNotHandledErr) }
        hotKey.action?()
        return noErr
    }
}
