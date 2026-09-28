import Foundation

public enum RecordStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case duplicateDay(CalendarDay)
}

/// Small, versioned, atomic local store for the first cross-platform contract.
/// Android can implement the same JSON schema while each platform owns I/O.
public final class FileRecordRepository: RecordRepository {
    private struct StoreFile: Codable {
        let schemaVersion: Int
        var logs: [DailyLog]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func log(for day: CalendarDay) throws -> DailyLog {
        lock.lock()
        defer { lock.unlock() }
        let store = try load()
        if let existing = store.logs.first(where: { $0.day == day }) {
            return existing
        }
        return try DailyLog(day: day)
    }

    public func save(_ log: DailyLog) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = try load()
        if let index = store.logs.firstIndex(where: { $0.day == log.day }) {
            store.logs[index] = log
        } else {
            store.logs.append(log)
        }
        store.logs.sort { $0.day < $1.day }
        try write(store)
    }

    public func allLogs() throws -> [DailyLog] {
        lock.lock()
        defer { lock.unlock() }
        return try load().logs
    }

    private func load() throws -> StoreFile {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return StoreFile(schemaVersion: 1, logs: [])
        }
        let store = try JSONDecoder().decode(StoreFile.self, from: Data(contentsOf: fileURL))
        guard store.schemaVersion == 1 else {
            throw RecordStoreError.unsupportedSchema(store.schemaVersion)
        }
        var days = Set<CalendarDay>()
        for log in store.logs {
            guard days.insert(log.day).inserted else {
                throw RecordStoreError.duplicateDay(log.day)
            }
        }
        return store
    }

    private func write(_ store: StoreFile) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(store).write(to: fileURL, options: .atomic)
    }
}
