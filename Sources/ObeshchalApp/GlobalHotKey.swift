import AppKit
import Carbon

@MainActor
final class GlobalHotKey {
    static let defaultKeyCode: UInt32 = 49
    static let defaultModifiers = UInt32(controlKey | optionKey)

    private static let signature: OSType = 0x4F425343
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    init() {}

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        guard keyCode <= 127,
              ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode),
              modifiers & UInt32(cmdKey | controlKey) != 0 else {
            throw HotKeyError.invalidShortcut
        }

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == 0x4F425343, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().handler?()
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
            guard status == noErr else { throw HotKeyError.registrationFailed(status) }
        }

        unregister()
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }
        self.handler = handler
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        handler = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    static func description(keyCode: UInt32, modifiers: UInt32) -> String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        let keys: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Пробел", 50: "`", 51: "⌫",
            65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 76: "⌤", 78: "−", 81: "=", 82: "0", 83: "1",
            84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 96: "F5", 97: "F6",
            98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
            119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return prefix + (keys[keyCode] ?? "Клавиша \(keyCode)")
    }

    private enum HotKeyError: LocalizedError {
        case invalidShortcut
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidShortcut:
                return "Выберите клавишу вместе с ⌘ или ⌃. Можно также добавить ⌥ и ⇧."
            case .registrationFailed(let status) where status == eventHotKeyExistsErr:
                return "Это сочетание уже занято. Выберите другое. Окно по-прежнему можно открыть из строки меню."
            case .registrationFailed(let status):
                return "Не удалось зарегистрировать сочетание клавиш (код \(status)). Выберите другое или откройте окно из строки меню."
            }
        }
    }
}
