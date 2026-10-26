import ObeshchalCore
import SwiftUI

private typealias CaptureState<Value> = SwiftUI.State<Value>

struct QuickCaptureView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focusedField: Field?
    @CaptureState private var showsDetails = false
    @CaptureState private var showsNewWorkspace = false

    private enum Field: Hashable {
        case text, person, link, note
    }

    var body: some View {
        surface
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: CaptureSizeKey.self, value: geometry.size)
                }
            }
            .onPreferenceChange(CaptureSizeKey.self) { size in
                model.onCaptureSizeChange?(size)
            }
            .onAppear {
                showsDetails = !model.draft.link.isEmpty || !model.draft.note.isEmpty
                focusedField = .text
            }
            .onReceive(NotificationCenter.default.publisher(for: .obeshchalFocusInput)) { _ in
                focusedField = .text
            }
            .onChange(of: model.draft.editingID) { _, _ in
                showsDetails = !model.draft.link.isEmpty || !model.draft.note.isEmpty
                focusedField = .text
            }
            .onExitCommand {
                model.dismissWindow()
            }
            .sheet(isPresented: $showsNewWorkspace, onDismiss: { focusedField = .text }) {
                WorkspaceCreationSheet(model: model)
            }
            .modifier(ModelErrorAlert(model: model, surface: .capture))
    }

    @ViewBuilder
    private var surface: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        #else
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.draft.editingID == nil ? "Быстрое обещание" : "Изменить обещание")
                    .font(.headline)
                Spacer()
                if model.draft.editingID != nil {
                    Button("Отмена") {
                        model.cancelEditing()
                        focusedField = .text
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    model.dismissWindow()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Скрыть · Esc")
                .accessibilityLabel("Скрыть окно")
            }

            if model.isReadOnly {
                Label("Хранилище недоступно. Восстанови данные в списке обещаний.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Что обещал?", text: $model.draft.text)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .text)
                    .onSubmit(save)
                    .accessibilityLabel("Что обещал")

                Divider()

                HStack(spacing: 10) {
                    TextField("Кому", text: $model.draft.person)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .person)
                        .onSubmit(save)
                        .accessibilityLabel("Кому обещал")

                    Toggle("Есть срок", isOn: $model.draft.hasDueDate)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .help("Установить срок")

                    DatePicker("Срок", selection: $model.draft.dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .disabled(!model.draft.hasDueDate)
                }

                HStack(spacing: 8) {
                    Text("Пространство")
                        .foregroundStyle(.secondary)
                    Picker("Пространство", selection: Binding(
                        get: { model.activeWorkspaceID },
                        set: { model.selectWorkspace($0) }
                    )) {
                        ForEach(model.archive.workspaces) { workspace in
                            Text(workspace.name).tag(workspace.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Button {
                        showsNewWorkspace = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Создать пространство")
                    .accessibilityLabel("Создать пространство")
                }

                DisclosureGroup("Ссылка и заметка", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ссылка на Jira или другой ресурс", text: $model.draft.link)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .link)
                            .onSubmit(save)
                            .accessibilityLabel("Ссылка")
                        Text("Заметка")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $model.draft.note)
                            .font(.body)
                            .frame(height: 64)
                            .focused($focusedField, equals: .note)
                            .accessibilityLabel("Заметка")
                    }
                    .padding(.top, 8)
                }
                .font(.callout)
            }
            .disabled(model.isReadOnly)

            HStack {
                Button("Все обещания") {
                    model.showOverview()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Сохранить", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        guard model.canSave else { return }
        model.saveDraft()
    }
}

private struct CaptureSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
