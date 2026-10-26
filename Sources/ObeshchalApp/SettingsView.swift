import AppKit
import Carbon
import ObeshchalCore
import SwiftUI

private typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState private var shortcutHint = "Нажмите поле и введите сочетание с ⌘ или ⌃."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Быстрое обещание")
                .font(.title2.bold())
            Text("Сочетание открывает окно из любого приложения.")
                .foregroundStyle(.secondary)

            HStack {
                Text("Горячая клавиша")
                Spacer()
                ShortcutRecorder(description: model.hotKeyDescription, onRecord: { keyCode, modifiers in
                    let saved = model.setHotKey(keyCode: keyCode, modifiers: modifiers)
                    if saved { shortcutHint = "Сочетание сохранено." }
                    return saved
                }, onInvalid: {
                    shortcutHint = "Добавьте ⌘ или ⌃. Escape отменяет ввод."
                })
                .frame(width: 170, height: 28)
            }

            Text(shortcutHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Вернуть ⌃⌥Пробел") {
                if model.setHotKey(keyCode: GlobalHotKey.defaultKeyCode, modifiers: GlobalHotKey.defaultModifiers) {
                    shortcutHint = "Сочетание по умолчанию восстановлено."
                }
            }
            Divider()

            Section {
                Picker("Положение", selection: $model.capturePosition) {
                    ForEach(CapturePosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.menu)

                Text("На экране, где находится курсор. Положение применяется при следующем открытии.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Всплывающее окно")
                    .font(.headline)
            }

            Divider()
            Text("Все обещания хранятся на этом Mac. Для резервной копии используйте экспорт в главном окне.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 420)
        .alert("Не удалось изменить сочетание", isPresented: Binding(
            get: { model.errorMessage != nil && model.activeSurface == .settings },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let description: String
    let onRecord: (UInt32, UInt32) -> Bool
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> ShortcutField {
        let field = ShortcutField()
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.focusRingType = .exterior
        field.setAccessibilityLabel("Горячая клавиша")
        field.setAccessibilityHelp("Нажмите и введите сочетание с Command или Control. Escape отменяет ввод.")
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: ShortcutField, context: Context) {
        field.shortcutDescription = description
        field.onRecord = onRecord
        field.onInvalid = onInvalid
        if field.window?.firstResponder !== field { field.stringValue = description }
    }
}

private final class ShortcutField: NSTextField {
    var shortcutDescription = ""
    var onRecord: ((UInt32, UInt32) -> Bool)?
    var onInvalid: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        stringValue = "Нажмите сочетание…"
        return true
    }

    override func resignFirstResponder() -> Bool {
        stringValue = shortcutDescription
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else {
            onInvalid?()
            NSSound.beep()
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if onRecord?(UInt32(event.keyCode), modifiers) == true {
            window?.makeFirstResponder(nil)
        }
    }
}
