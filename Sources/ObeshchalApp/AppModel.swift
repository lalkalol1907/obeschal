import AppKit
import Combine
import Foundation
import ObeshchalCore
import UniformTypeIdentifiers

extension Notification.Name {
    static let obeshchalFocusInput = Notification.Name("obeshchalFocusInput")
}

enum AppSurface { case capture, overview, settings }

@MainActor
final class AppModel: ObservableObject {
    @Published var archive: ObeshchalArchive
    @Published var activeWorkspaceID: UUID
    @Published var filter: RecordFilter = .today
    @Published var draft = PromiseDraft()
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var activeSurface: AppSurface = .capture
    @Published private(set) var isReadOnly = false
    @Published private(set) var hotKeyCode: UInt32
    @Published private(set) var hotKeyModifiers: UInt32
    @Published private var today = LocalDay.today

    var onShowWindow: (() -> Void)?
    var onShowOverview: (() -> Void)?
    var onDismissWindow: (() -> Void)?
    var onCaptureSizeChange: ((CGSize) -> Void)?

    private let repository: PromiseRepository
    private let storeURL: URL
    private let defaults = UserDefaults.standard
    private let hotKey = GlobalHotKey()
    private var dayTimer: Timer?
    private var workspaceDrafts: [UUID: PromiseDraft] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = ProcessInfo.processInfo.environment["OBESHCHAL_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? support.appendingPathComponent("Obeshchal", isDirectory: true)
        storeURL = directory.appendingPathComponent("promises.json")
        repository = PromiseRepository(fileURL: storeURL)
        var initial = ObeshchalArchive.fresh()
        var loadingError: Error?
        do {
            if let loaded = try repository.load() {
                initial = loaded
            } else {
                try repository.save(initial)
            }
        } catch {
            loadingError = error
        }
        archive = initial
        let savedSpace = defaults.string(forKey: "activeWorkspaceID").flatMap(UUID.init(uuidString:))
        activeWorkspaceID = initial.workspaces.first(where: { $0.id == savedSpace })?.id ?? initial.workspaces[0].id
        hotKeyCode = (defaults.object(forKey: "hotKeyCode") as? NSNumber)?.uint32Value ?? GlobalHotKey.defaultKeyCode
        hotKeyModifiers = (defaults.object(forKey: "hotKeyModifiers") as? NSNumber)?.uint32Value ?? GlobalHotKey.defaultModifiers
        if let loadingError {
            isReadOnly = true
            errorMessage = "Не удалось открыть хранилище. Файл не изменён. Можно импортировать резервную копию.\n\(storeURL.path)\n\n\(loadingError.localizedDescription)"
        }
        dayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDay() }
        }
    }

    var activeWorkspaceName: String {
        archive.workspaces.first(where: { $0.id == activeWorkspaceID })?.name ?? "Личное"
    }

    var visibleRecords: [PromiseRecord] {
        archive.filteredRecords(workspaceID: activeWorkspaceID, filter: filter, today: today)
    }

    var canSave: Bool { !isReadOnly && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hotKeyDescription: String { GlobalHotKey.description(keyCode: hotKeyCode, modifiers: hotKeyModifiers) }

    func refreshDay() {
        if today != .today {
            today = .today
            draft.refreshDefaultDate()
            for id in Array(workspaceDrafts.keys) { workspaceDrafts[id]?.refreshDefaultDate() }
        }
    }

    func showCapture() { onShowWindow?() }
    func showOverview() { onShowOverview?() }

    func configureHotKey() {
        do {
            try hotKey.register(keyCode: hotKeyCode, modifiers: hotKeyModifiers) { [weak self] in self?.onShowWindow?() }
        } catch {
            errorMessage = "Не удалось включить хоткей \(hotKeyDescription). Выбери другую комбинацию в настройках. Окно можно открыть через строку меню.\n\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func setHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        do {
            try hotKey.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in self?.onShowWindow?() }
            hotKeyCode = keyCode
            hotKeyModifiers = modifiers
            defaults.set(keyCode, forKey: "hotKeyCode")
            defaults.set(modifiers, forKey: "hotKeyModifiers")
            return true
        } catch {
            let registrationError = error
            do {
                try hotKey.register(keyCode: hotKeyCode, modifiers: hotKeyModifiers) { [weak self] in self?.onShowWindow?() }
                errorMessage = "Эта комбинация недоступна. Предыдущий хоткей сохранён.\n\n\(registrationError.localizedDescription)"
            } catch {
                errorMessage = "Хоткей недоступен. Открой приложение через строку меню и выбери другую комбинацию.\n\n\(registrationError.localizedDescription)"
            }
            return false
        }
    }

    func selectWorkspace(_ id: UUID) {
        guard id != activeWorkspaceID, archive.workspaces.contains(where: { $0.id == id }) else { return }
        workspaceDrafts[activeWorkspaceID] = draft
        activeWorkspaceID = id
        draft = workspaceDrafts.removeValue(forKey: id) ?? PromiseDraft()
        draft.refreshDefaultDate()
        defaults.set(id.uuidString, forKey: "activeWorkspaceID")
        NotificationCenter.default.post(name: .obeshchalFocusInput, object: nil)
    }

    @discardableResult
    func createWorkspace(name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "Введи название пространства."; return false }
        guard !archive.workspaces.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            errorMessage = "Пространство с таким названием уже есть."
            return false
        }
        let workspace = Workspace(name: name)
        var next = archive
        next.workspaces.append(workspace)
        guard commit(next) else { return false }
        selectWorkspace(workspace.id)
        return true
    }

    func saveDraft() {
        guard canSave else { return }
        var next = archive
        let existing = draft.editingID.flatMap { id in next.records.first(where: { $0.id == id }) }
        var record = existing ?? PromiseRecord(workspaceID: activeWorkspaceID, text: "")
        record.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        record.person = draft.person.trimmingCharacters(in: .whitespacesAndNewlines)
        record.dueDate = draft.hasDueDate ? LocalDay(draft.dueDate) : nil
        record.link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        record.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = next.records.firstIndex(where: { $0.id == record.id }) {
            next.records[index] = record
        } else {
            next.records.append(record)
        }
        guard commit(next) else { return }
        draft = PromiseDraft()
        infoMessage = nil
        dismissWindow()
    }

    func edit(_ record: PromiseRecord) {
        guard !isReadOnly else { return }
        if draft.editingID == record.id {
            showCapture()
            return
        }
        if hasUnsavedDraftChanges {
            let alert = NSAlert()
            alert.messageText = "Заменить незавершённый ввод?"
            alert.informativeText = "Сейчас в форме есть несохранённые изменения. Можно продолжить ввод или открыть выбранное обещание."
            alert.addButton(withTitle: "Продолжить ввод")
            alert.addButton(withTitle: "Заменить")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        draft = PromiseDraft(editingID: record.id, text: record.text, person: record.person,
            hasDueDate: record.dueDate != nil, dueDate: record.dueDate?.date ?? Date(), link: record.link, note: record.note)
        showCapture()
        NotificationCenter.default.post(name: .obeshchalFocusInput, object: nil)
    }

    func cancelEditing() { draft = PromiseDraft() }

    func toggleCompleted(_ record: PromiseRecord) {
        var next = archive
        guard let index = next.records.firstIndex(where: { $0.id == record.id }) else { return }
        next.records[index].completedAt = record.completedAt == nil ? Date() : nil
        _ = commit(next)
    }

    func toggleToday(_ record: PromiseRecord) {
        var next = archive
        guard let index = next.records.firstIndex(where: { $0.id == record.id }) else { return }
        next.records[index].isInToday.toggle()
        _ = commit(next)
    }

    func delete(_ record: PromiseRecord) {
        var next = archive
        next.records.removeAll(where: { $0.id == record.id })
        if commit(next), draft.editingID == record.id { cancelEditing() }
    }

    func dismissWindow() { onDismissWindow?() }

    func exportArchive() {
        guard !isReadOnly else {
            errorMessage = "Экспорт недоступен: исходные данные не удалось прочитать. Сначала восстанови хранилище через импорт резервной копии. Исходный файл не изменён."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Экспорт обещаний"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Обещал-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try archive.encoded().write(to: url, options: .atomic)
            infoMessage = "Резервная копия сохранена."
        } catch { errorMessage = "Не удалось экспортировать данные.\n\(error.localizedDescription)" }
    }

    func importArchive() {
        let panel = NSOpenPanel()
        panel.title = "Импорт обещаний"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try ObeshchalArchive.decode(Data(contentsOf: url))
            let result = try archive.merging(imported)
            if isReadOnly {
                let alert = NSAlert()
                alert.messageText = "Восстановить хранилище?"
                alert.informativeText = "Перед импортом исходный файл будет сохранён рядом с хранилищем как резервная копия."
                alert.addButton(withTitle: "Восстановить")
                alert.addButton(withTitle: "Отмена")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                if FileManager.default.fileExists(atPath: storeURL.path) {
                    let backupURL = storeURL.deletingPathExtension().appendingPathExtension("backup-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: storeURL, to: backupURL)
                }
            }
            try repository.save(result.archive)
            archive = result.archive
            isReadOnly = false
            errorMessage = nil
            infoMessage = "Добавлено записей: \(result.addedRecords), пространств: \(result.addedWorkspaces)."
        } catch { errorMessage = "Импорт не выполнен. Данные не изменены.\n\(error.localizedDescription)" }
    }

    private func commit(_ next: ObeshchalArchive) -> Bool {
        guard !isReadOnly else { errorMessage = "Хранилище недоступно для записи. Импортируй резервную копию для восстановления."; return false }
        do {
            try repository.save(next)
            archive = next
            return true
        } catch {
            errorMessage = "Не удалось сохранить. Ввод и прежние данные сохранены.\n\(error.localizedDescription)"
            return false
        }
    }

    private var hasUnsavedDraftChanges: Bool {
        if let id = draft.editingID, let record = archive.records.first(where: { $0.id == id }) {
            return draft.text != record.text || draft.person != record.person || draft.link != record.link
                || draft.note != record.note || draft.hasDueDate != (record.dueDate != nil)
                || (draft.hasDueDate && LocalDay(draft.dueDate) != record.dueDate)
        }
        return !draft.text.isEmpty || !draft.person.isEmpty || !draft.link.isEmpty || !draft.note.isEmpty
            || !draft.hasDueDate || LocalDay(draft.dueDate) != .today
    }
}
