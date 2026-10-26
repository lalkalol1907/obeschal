import Foundation
import Testing
@testable import ObeshchalCore

private func day(_ value: String) throws -> LocalDay {
    try JSONDecoder().decode(LocalDay.self, from: Data("\"\(value)\"".utf8))
}

private func record(
    _ name: String,
    workspace: Workspace,
    due: LocalDay? = nil,
    inToday: Bool = false,
    completed: Date? = nil
) -> PromiseRecord {
    PromiseRecord(
        workspaceID: workspace.id, text: name, dueDate: due, isInToday: inToday,
        createdAt: Date(timeIntervalSince1970: 100), completedAt: completed
    )
}

@Test func todayIncludesOverdueAndManualRecordsOnceAndIsolatesSpaces() throws {
    let personal = Workspace(name: "Личное")
    let work = Workspace(name: "Работа")
    let yesterday = try day("2026-10-25")
    let today = try day("2026-10-26")
    let tomorrow = try day("2026-10-27")
    let records = [
        record("Просрочено", workspace: personal, due: yesterday),
        record("Сегодня и вручную", workspace: personal, due: today, inToday: true),
        record("Завтра вручную", workspace: personal, due: tomorrow, inToday: true),
        record("Без срока вручную", workspace: personal, inToday: true),
        record("Завтра", workspace: personal, due: tomorrow),
        record("Выполнено", workspace: personal, due: yesterday, completed: Date()),
        record("Из работы", workspace: work, due: yesterday)
    ]
    let archive = ObeshchalArchive(workspaces: [personal, work], records: records)
    #expect(archive.filteredRecords(workspaceID: personal.id, filter: .today, today: today).map(\.text) == [
        "Просрочено", "Сегодня и вручную", "Завтра вручную", "Без срока вручную"
    ])
    #expect(archive.filteredRecords(workspaceID: work.id, filter: .today, today: today).map(\.text) == ["Из работы"])
    #expect(archive.filteredRecords(workspaceID: personal.id, filter: .all).count == 5)
}

@Test func completionAndRestorationMoveRecordBetweenFilters() throws {
    var archive = ObeshchalArchive.fresh()
    let workspace = archive.workspaces[0]
    archive.records = [record("Позвонить", workspace: workspace, due: .today)]
    archive.records[0].completedAt = Date()
    #expect(archive.filteredRecords(workspaceID: workspace.id, filter: .today).isEmpty)
    #expect(archive.filteredRecords(workspaceID: workspace.id, filter: .all).isEmpty)
    #expect(archive.filteredRecords(workspaceID: workspace.id, filter: .completed).count == 1)
    archive.records[0].completedAt = nil
    #expect(archive.filteredRecords(workspaceID: workspace.id, filter: .today).count == 1)
    #expect(archive.filteredRecords(workspaceID: workspace.id, filter: .completed).isEmpty)
}

@Test func sortingIsDeterministicWithUnscheduledLastAndNewestCompletionFirst() throws {
    let space = Workspace(name: "Личное")
    let today = try day("2026-10-26")
    var a = record("A", workspace: space, due: today)
    var b = record("B", workspace: space, due: today)
    a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    var archive = ObeshchalArchive(workspaces: [space], records: [
        b, record("Без срока", workspace: space), a
    ])
    #expect(archive.filteredRecords(workspaceID: space.id, filter: .all).map(\.text) == ["A", "B", "Без срока"])
    archive.records[0].completedAt = Date(timeIntervalSince1970: 200)
    archive.records[2].completedAt = Date(timeIntervalSince1970: 100)
    #expect(archive.filteredRecords(workspaceID: space.id, filter: .completed).map(\.text) == ["B", "A"])
}

@Test func localDaysStayCalendarDatesAndRejectImpossibleDates() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 59))!
    let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 0, minute: 1))!
    #expect(LocalDay(beforeMidnight) == (try day("2026-10-25")))
    #expect(LocalDay(afterMidnight) == (try day("2026-10-26")))
    #expect(LocalDay(beforeMidnight) < LocalDay(afterMidnight))
    #expect(LocalDay(try day("2026-10-26").date) == (try day("2026-10-26")))
    #expect(try day("2024-02-29") < day("2024-03-01"))
    for invalid in ["2026-02-29", "2026-02-30", "2026-13-01", "2026-00-01", "0000-01-01", "2026-1-01", "2026-01-32"] {
        #expect(throws: (any Error).self) { try day(invalid) }
    }
}

@Test func archiveRoundTripAndRepositoryPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = PromiseRepository(fileURL: directory.appendingPathComponent("nested/promises.json"))
    #expect(try repository.load() == nil)
    var archive = ObeshchalArchive.fresh()
    archive.workspaces.append(Workspace(name: "Работа"))
    archive.records = [PromiseRecord(
        workspaceID: archive.workspaces[1].id, text: "Отправить отчёт", person: "Аня",
        dueDate: try day("2026-10-26"), link: "https://jira.example.com/browse/APP-123",
        note: "Сводка за октябрь", isInToday: true
    )]
    #expect(try ObeshchalArchive.decode(archive.encoded()) == archive)
    try repository.save(archive)
    #expect(try repository.load() == archive)
    archive.records[0].completedAt = Date()
    try repository.save(archive)
    #expect(try repository.load() == archive)
}

@Test func corruptAndUnsupportedFilesFailWithoutReplacingExistingBytes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("promises.json")
    let data = Data("{broken json}".utf8)
    try data.write(to: file)
    let repository = PromiseRepository(fileURL: file)
    #expect(throws: ArchiveError.self) { try repository.load() }
    #expect(try Data(contentsOf: file) == data)
    let unsupported = ObeshchalArchive(version: 99, workspaces: [Workspace(name: "Личное")], records: [])
    let invalidData = try JSONEncoder().encode(unsupported)
    #expect(throws: ArchiveError.unsupportedVersion(99)) { try ObeshchalArchive.decode(invalidData) }
    #expect(throws: ArchiveError.self) { try repository.save(unsupported) }
    #expect(try Data(contentsOf: file) == data)
}

@Test func importKeepsExistingIDsAndMapsMatchingSpaceNames() throws {
    let personal = Workspace(name: "Личное")
    let work = Workspace(name: "Работа")
    let existing = record("Мой текст", workspace: work)
    let archive = ObeshchalArchive(workspaces: [personal, work], records: [existing])
    let importedWork = Workspace(name: "  РАБОТА\n")
    let other = Workspace(name: "Дом")
    var replacement = existing
    replacement.text = "Не заменять"
    replacement.workspaceID = importedWork.id
    let imported = ObeshchalArchive(workspaces: [importedWork, other], records: [
        replacement,
        record("Новая рабочая", workspace: importedWork),
        record("Домашняя", workspace: other)
    ])
    let merged = try archive.merging(imported)
    #expect(merged.addedRecords == 2)
    #expect(merged.addedWorkspaces == 1)
    #expect(merged.archive.records.first == existing)
    #expect(merged.archive.records[1].workspaceID == work.id)
    #expect(merged.archive.records[2].workspaceID == other.id)
    #expect(try merged.archive.merging(imported).addedRecords == 0)
    #expect(try ObeshchalArchive.decode(merged.archive.encoded()) == merged.archive)
}

@Test func importSpaceIDTakesPrecedenceOverName() throws {
    let personal = Workspace(name: "Личное")
    let work = Workspace(name: "Работа")
    let archive = ObeshchalArchive(workspaces: [personal, work], records: [])
    let renamedPersonal = Workspace(id: personal.id, name: work.name)
    let imported = ObeshchalArchive(workspaces: [renamedPersonal], records: [record("Пример", workspace: renamedPersonal)])
    let merged = try archive.merging(imported)
    #expect(merged.addedWorkspaces == 0)
    #expect(merged.archive.workspaces == archive.workspaces)
    #expect(merged.archive.records[0].workspaceID == personal.id)
}

@Test func invalidArchivesAreRejectedBeforeImport() throws {
    let original = ObeshchalArchive.fresh()
    let space = original.workspaces[0]
    let one = record("Текст", workspace: space)
    let invalidArchives = [
        ObeshchalArchive(workspaces: [], records: []),
        ObeshchalArchive(workspaces: [space, space], records: []),
        ObeshchalArchive(workspaces: [Workspace(name: " \n")], records: []),
        ObeshchalArchive(workspaces: [space], records: [one, one]),
        ObeshchalArchive(workspaces: [space], records: [record("Текст", workspace: Workspace(name: "Нет"))]),
        ObeshchalArchive(workspaces: [space], records: [record(" \n", workspace: space)])
    ]
    for invalid in invalidArchives {
        #expect(throws: ArchiveError.self) { try original.merging(invalid) }
        #expect(throws: ArchiveError.self) { try ObeshchalArchive.decode(JSONEncoder().encode(invalid)) }
    }
    #expect(original.records.isEmpty)
}

@Test func linksAcceptOnlyAbsoluteWebAddresses() throws {
    let space = Workspace(name: "Работа")
    for link in ["", "http://example.com", "https://jira.example.com/browse/APP-123?view=all#task", "HTTPS://example.com/path"] {
        let archive = ObeshchalArchive(workspaces: [space], records: [
            PromiseRecord(workspaceID: space.id, text: "Задача", link: link)
        ])
        #expect(try ObeshchalArchive.decode(archive.encoded()) == archive)
    }
    for link in ["jira.example.com/APP-123", "/APP-123", "file:///etc/passwd", "javascript:alert(1)", "https:///APP-123", "https://exa mple.com", " https://example.com"] {
        let archive = ObeshchalArchive(workspaces: [space], records: [
            PromiseRecord(workspaceID: space.id, text: "Задача", link: link)
        ])
        #expect(throws: ArchiveError.self) { try archive.encoded() }
    }
}
