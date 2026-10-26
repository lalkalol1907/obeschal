import Foundation

public struct PromiseDraft {
    public var editingID: UUID?
    public var text: String
    public var person: String
    public var hasDueDate: Bool
    public var dueDate: Date {
        didSet { usesDefaultDueDate = false }
    }
    public var link: String
    public var note: String
    public private(set) var usesDefaultDueDate: Bool

    public init(
        editingID: UUID? = nil,
        text: String = "",
        person: String = "",
        hasDueDate: Bool = true,
        dueDate: Date = Date(),
        link: String = "",
        note: String = ""
    ) {
        self.editingID = editingID
        self.text = text
        self.person = person
        self.hasDueDate = hasDueDate
        self.dueDate = dueDate
        self.link = link
        self.note = note
        usesDefaultDueDate = editingID == nil
    }

    public mutating func refreshDefaultDate(now: Date = Date()) {
        if editingID == nil && hasDueDate && usesDefaultDueDate {
            dueDate = now
            usesDefaultDueDate = true
        }
    }
}
