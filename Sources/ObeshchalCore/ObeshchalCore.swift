import Foundation

/// A Gregorian calendar day, stored independently of time and time zone.
public struct LocalDay: Codable, Hashable, Comparable, Sendable {
    private let year: Int
    private let month: Int
    private let day: Int

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    public init(_ date: Date = Date()) {
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    public var date: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static var today: LocalDay { LocalDay() }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2,
              parts[2].count == 2, value.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) }),
              let year = Int(parts[0]), (1...9999).contains(year),
              let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Некорректная дата: \(value)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Несуществующая дата: \(value)")
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Несуществующая дата: \(value)")
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }
}

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct PromiseRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var text: String
    public var person: String
    public var dueDate: LocalDay?
    public var link: String
    public var note: String
    public var isInToday: Bool
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        workspaceID: UUID,
        text: String,
        person: String = "",
        dueDate: LocalDay? = .today,
        link: String = "",
        note: String = "",
        isInToday: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.text = text
        self.person = person
        self.dueDate = dueDate
        self.link = link
        self.note = note
        self.isInToday = isInToday
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public enum RecordFilter: CaseIterable, Hashable, Sendable {
    case today, all, completed
}

public enum ArchiveError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Версия файла \(version) не поддерживается."
        case .invalidData(let message):
            return "Файл содержит некорректные данные: \(message)"
        }
    }
}

public struct ObeshchalArchive: Codable, Equatable, Sendable {
    public var version: Int
    public var workspaces: [Workspace]
    public var records: [PromiseRecord]

    public init(version: Int = 1, workspaces: [Workspace], records: [PromiseRecord]) {
        self.version = version
        self.workspaces = workspaces
        self.records = records
    }

    public static func fresh() -> ObeshchalArchive {
        ObeshchalArchive(workspaces: [Workspace(name: "Личное")], records: [])
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ObeshchalArchive {
        let archive: ObeshchalArchive
        do {
            archive = try JSONDecoder().decode(ObeshchalArchive.self, from: data)
        } catch {
            throw ArchiveError.invalidData("не удалось прочитать JSON или его поля.")
        }
        try archive.validate()
        return archive
    }

    public func merging(_ imported: ObeshchalArchive) throws -> (
        archive: ObeshchalArchive, addedRecords: Int, addedWorkspaces: Int
    ) {
        try validate()
        try imported.validate()
        var result = self
        var workspaceIDs: [UUID: UUID] = [:]
        for workspace in imported.workspaces {
            if let existing = result.workspaces.first(where: { $0.id == workspace.id }) {
                workspaceIDs[workspace.id] = existing.id
            } else if let existing = result.workspaces.first(where: {
                Self.workspaceName($0.name) == Self.workspaceName(workspace.name)
            }) {
                workspaceIDs[workspace.id] = existing.id
            } else {
                result.workspaces.append(workspace)
                workspaceIDs[workspace.id] = workspace.id
            }
        }
        var existingRecordIDs = Set(records.map(\.id))
        for var record in imported.records where !existingRecordIDs.contains(record.id) {
            record.workspaceID = workspaceIDs[record.workspaceID]!
            result.records.append(record)
            existingRecordIDs.insert(record.id)
        }
        return (result, result.records.count - records.count, result.workspaces.count - workspaces.count)
    }

    public func filteredRecords(
        workspaceID: UUID,
        filter: RecordFilter,
        today: LocalDay = .today
    ) -> [PromiseRecord] {
        records.filter { record in
            guard record.workspaceID == workspaceID else { return false }
            switch filter {
            case .today:
                return record.completedAt == nil &&
                    (record.isInToday || record.dueDate.map { $0 <= today } == true)
            case .all:
                return record.completedAt == nil
            case .completed:
                return record.completedAt != nil
            }
        }.sorted { lhs, rhs in
            if case .completed = filter, lhs.completedAt != rhs.completedAt {
                return lhs.completedAt! > rhs.completedAt!
            }
            if lhs.dueDate != rhs.dueDate {
                switch (lhs.dueDate, rhs.dueDate) {
                case (.some(let left), .some(let right)): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): break
                }
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func workspaceName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func validate() throws {
        guard version == 1 else { throw ArchiveError.unsupportedVersion(version) }
        guard !workspaces.isEmpty else { throw ArchiveError.invalidData("нет пространств.") }
        guard Set(workspaces.map(\.id)).count == workspaces.count else {
            throw ArchiveError.invalidData("повторяются идентификаторы пространств.")
        }
        guard Set(records.map(\.id)).count == records.count else {
            throw ArchiveError.invalidData("повторяются идентификаторы обещаний.")
        }
        guard workspaces.allSatisfy({ !Self.workspaceName($0.name).isEmpty }) else {
            throw ArchiveError.invalidData("пустое название пространства.")
        }
        let workspaceIDs = Set(workspaces.map(\.id))
        for record in records {
            guard workspaceIDs.contains(record.workspaceID) else {
                throw ArchiveError.invalidData("обещание ссылается на отсутствующее пространство.")
            }
            guard !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArchiveError.invalidData("пустой текст обещания.")
            }
            guard record.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  record.completedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
                throw ArchiveError.invalidData("некорректное время создания или выполнения.")
            }
            if !record.link.isEmpty {
                guard let url = URLComponents(string: record.link),
                      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      let host = url.host, !host.isEmpty,
                      !record.link.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
                      url.url != nil else {
                    throw ArchiveError.invalidData("ссылка должна быть полным адресом http:// или https://.")
                }
            }
        }
    }
}

public struct PromiseRepository {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ObeshchalArchive? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        return try ObeshchalArchive.decode(data)
    }

    public func save(_ archive: ObeshchalArchive) throws {
        let data = try archive.encoded()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
