import AppKit
import ObeshchalCore
import SwiftUI

private typealias ViewState<Value> = SwiftUI.State<Value>

struct MainView: View {
    @ObservedObject var model: AppModel
    @ViewState private var showsNewWorkspace = false
    @ViewState private var recordToDelete: PromiseRecord?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<UUID?>(
                get: { model.activeWorkspaceID },
                set: { if let id = $0 { model.selectWorkspace(id) } }
            )) {
                Section("Пространства") {
                    ForEach(model.archive.workspaces) { workspace in
                        Label(workspace.name, systemImage: "folder")
                            .tag(workspace.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Обещал")
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        showsNewWorkspace = true
                    } label: {
                        Label("Новое пространство", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isReadOnly)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        } detail: {
            VStack(spacing: 0) {
                if model.isReadOnly {
                    Label("Хранилище недоступно. Импортируй резервную копию через меню «Данные».", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Divider()
                }

                if let message = model.infoMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                        Text(message)
                        Spacer(minLength: 0)
                        Button {
                            model.infoMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Закрыть сообщение")
                    }
                    .font(.callout)
                    .padding(12)
                    Divider()
                }

                Picker("Показать обещания", selection: $model.filter) {
                    Text("Сегодня").tag(RecordFilter.today)
                    Text("Все").tag(RecordFilter.all)
                    Text("Выполнено").tag(RecordFilter.completed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)

                List {
                    ForEach(model.visibleRecords) { record in
                        recordRow(record)
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if model.visibleRecords.isEmpty { emptyState }
                }

                HStack {
                    Text("Обещаний: \(model.visibleRecords.count)")
                    Spacer()
                    Text("На этом Mac")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .navigationTitle(model.activeWorkspaceName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.showCapture()
                    } label: {
                        Label("Новое обещание", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.isReadOnly)
                }
                ToolbarItem {
                    Menu {
                        Button("Экспортировать…", systemImage: "square.and.arrow.up") { model.exportArchive() }
                        Button("Импортировать…", systemImage: "square.and.arrow.down") { model.importArchive() }
                    } label: {
                        Label("Данные", systemImage: "externaldrive")
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .sheet(isPresented: $showsNewWorkspace) {
            WorkspaceCreationSheet(model: model)
        }
        .modifier(ModelErrorAlert(model: model, surface: .overview))
        .confirmationDialog("Удалить обещание?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        ), titleVisibility: .visible, presenting: recordToDelete) { record in
            Button("Удалить", role: .destructive) {
                model.delete(record)
                recordToDelete = nil
            }
            Button("Отмена", role: .cancel) { recordToDelete = nil }
        } message: { record in
            Text(record.text)
        }
    }

    private func recordRow(_ record: PromiseRecord) -> some View {
        let isCompleted = record.completedAt != nil
        return HStack(alignment: .top, spacing: 10) {
            Button {
                model.toggleCompleted(record)
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isCompleted ? "Вернуть в работу" : "Отметить выполненным")
            .accessibilityLabel(isCompleted ? "Вернуть в работу" : "Отметить выполненным")
            .disabled(model.isReadOnly)

            Button {
                model.edit(record)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.text)
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    if !record.person.isEmpty || record.dueDate != nil {
                        HStack(spacing: 10) {
                            if !record.person.isEmpty {
                                Label(record.person, systemImage: "person")
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                            if let day = record.dueDate {
                                dueLabel(day, completed: isCompleted)
                            }
                        }
                        .font(.caption)
                    }

                    if !record.note.isEmpty {
                        Text(record.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Изменить обещание")

            if !record.link.isEmpty {
                Button {
                    openLink(record.link)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help(record.link)
                .accessibilityLabel("Открыть ссылку")
            }

            if !isCompleted {
                Button {
                    model.toggleToday(record)
                } label: {
                    Image(systemName: record.isInToday ? "pin.fill" : "pin")
                        .foregroundStyle(record.isInToday ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(record.isInToday ? "Снять отметку «Сегодня»" : "Добавить в «Сегодня»")
                .accessibilityLabel(record.isInToday ? "Снять отметку Сегодня" : "Добавить в Сегодня")
                .disabled(model.isReadOnly)
            }

            Menu {
                recordActions(record)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Действия с обещанием")
        }
        .padding(.vertical, 6)
        .contextMenu { recordActions(record) }
    }

    @ViewBuilder
    private func recordActions(_ record: PromiseRecord) -> some View {
        Button("Изменить", systemImage: "pencil") { model.edit(record) }
            .disabled(model.isReadOnly)
        Button(record.completedAt == nil ? "Выполнено" : "Вернуть в работу", systemImage: "checkmark.circle") {
            model.toggleCompleted(record)
        }
        .disabled(model.isReadOnly)
        if record.completedAt == nil {
            Button(record.isInToday ? "Снять отметку «Сегодня»" : "Добавить в «Сегодня»", systemImage: "pin") {
                model.toggleToday(record)
            }
            .disabled(model.isReadOnly)
        }
        if !record.link.isEmpty {
            Button("Открыть ссылку", systemImage: "arrow.up.right.square") { openLink(record.link) }
        }
        Divider()
        Button("Удалить…", systemImage: "trash", role: .destructive) { recordToDelete = record }
            .disabled(model.isReadOnly)
    }

    private func dueLabel(_ day: LocalDay, completed: Bool) -> some View {
        let overdue = day < .today && !completed
        return Label(overdue ? "Просрочено · \(dayText(day))" : dayText(day), systemImage: overdue ? "exclamationmark.circle" : "calendar")
            .foregroundStyle(overdue ? Color.red : Color.secondary)
    }

    private func dayText(_ day: LocalDay) -> String {
        if day == .today { return "Сегодня" }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))
        if Calendar.current.component(.year, from: day.date) == Calendar.current.component(.year, from: Date()) {
            return day.date.formatted(style)
        }
        return day.date.formatted(style.year())
    }

    private var emptyState: some View {
        let content: (symbol: String, title: String, detail: String)
        switch model.filter {
        case .today:
            content = ("sun.max", "На сегодня всё", "Здесь будут обещания на сегодня, просроченные и закреплённые вручную.")
        case .all:
            content = ("checkmark.bubble", "Пока нет обещаний", "Создай первое обещание в этом пространстве.")
        case .completed:
            content = ("checkmark.circle", "Пока ничего не выполнено", "Отмечай готовые обещания галочкой.")
        }
        return ContentUnavailableView(content.title, systemImage: content.symbol, description: Text(content.detail))
    }

    private func openLink(_ value: String) {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              NSWorkspace.shared.open(url) else {
            model.errorMessage = "Не удалось открыть ссылку. Проверь её адрес."
            return
        }
    }
}

struct WorkspaceCreationSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @ViewState private var name = ""
    @ViewState private var creationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Новое пространство")
                .font(.title2.weight(.semibold))
            Text("Например, «Личное», «Работа» или название проекта.")
                .foregroundStyle(.secondary)
            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(create)
                .accessibilityLabel("Название пространства")
            if let issue = creationError ?? duplicateMessage {
                Text(issue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Создать", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicateMessage != nil)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { nameFocused = true }
        .onChange(of: name) { _, _ in creationError = nil }
    }

    private var duplicateMessage: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return model.archive.workspaces.contains {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ? "Пространство с таким именем уже есть." : nil
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, duplicateMessage == nil else { return }
        if model.createWorkspace(name: name) {
            dismiss()
        } else {
            creationError = model.errorMessage ?? "Не удалось создать пространство."
            model.errorMessage = nil
        }
    }
}

struct ModelErrorAlert: ViewModifier {
    @ObservedObject var model: AppModel
    let surface: AppSurface

    func body(content: Content) -> some View {
        content.alert("Не удалось выполнить действие", isPresented: Binding(
            get: { model.errorMessage != nil && model.activeSurface == surface },
            set: { if !$0 && model.activeSurface == surface { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
