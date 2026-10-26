import Foundation
import Testing
import ObeshchalCore

private func draftDate(day: Int, hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@Test func defaultDraftFollowsTodayAcrossMultipleMidnights() {
    var draft = PromiseDraft(text: "Отправить отчёт", person: "Аня", dueDate: draftDate(day: 25, hour: 23))
    let firstMorning = draftDate(day: 26, hour: 8)
    draft.refreshDefaultDate(now: firstMorning)
    #expect(draft.dueDate == firstMorning)
    #expect(draft.usesDefaultDueDate)
    let secondMorning = draftDate(day: 27, hour: 8)
    draft.refreshDefaultDate(now: secondMorning)
    #expect(draft.dueDate == secondMorning)
    #expect(draft.text == "Отправить отчёт")
    #expect(draft.person == "Аня")
}

@Test func restoredWorkspaceDraftGetsCurrentDefaultDate() throws {
    let workspaceID = UUID()
    var cachedDrafts = [workspaceID: PromiseDraft(dueDate: draftDate(day: 25, hour: 23))]
    let cached = cachedDrafts.removeValue(forKey: workspaceID)
    var restored = try #require(cached)
    let nextMorning = draftDate(day: 26, hour: 8)
    restored.refreshDefaultDate(now: nextMorning)
    #expect(restored.dueDate == nextMorning)
    #expect(restored.usesDefaultDueDate)
}

@Test func manuallyChosenDeadlineSurvivesMidnight() {
    var draft = PromiseDraft(dueDate: draftDate(day: 25, hour: 23))
    let chosen = draftDate(day: 28, hour: 0)
    draft.dueDate = chosen
    draft.refreshDefaultDate(now: draftDate(day: 26, hour: 8))
    #expect(draft.dueDate == chosen)
    #expect(!draft.usesDefaultDueDate)
}

@Test func explicitlySelectingInitialDatePreservesThatDate() {
    let chosen = draftDate(day: 25, hour: 23)
    var draft = PromiseDraft(dueDate: chosen)
    draft.dueDate = chosen
    draft.refreshDefaultDate(now: draftDate(day: 26, hour: 8))
    #expect(draft.dueDate == chosen)
    #expect(!draft.usesDefaultDueDate)
}

@Test func editingExistingPromiseKeepsItsDeadline() {
    let deadline = draftDate(day: 25, hour: 0)
    var draft = PromiseDraft(editingID: UUID(), text: "Отредактировать", dueDate: deadline)
    draft.refreshDefaultDate(now: draftDate(day: 26, hour: 8))
    #expect(draft.dueDate == deadline)
    #expect(!draft.usesDefaultDueDate)
}

@Test func draftWithoutDeadlineStaysWithoutDeadline() {
    let originalDate = draftDate(day: 25, hour: 23)
    var draft = PromiseDraft(hasDueDate: false, dueDate: originalDate)
    draft.refreshDefaultDate(now: draftDate(day: 26, hour: 8))
    #expect(!draft.hasDueDate)
    #expect(draft.dueDate == originalDate)
}
