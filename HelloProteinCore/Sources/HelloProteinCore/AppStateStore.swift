import Foundation

public enum StoreInspection: Equatable {
    /// No store file. Nothing about the user can be concluded from this alone.
    case missing
    case ready(AppState)
    /// A schema 1 prototype file that only stored logs.
    case legacySchema1(logs: [DailyLog])
    case unsupportedSchema(Int)
    /// The file exists but cannot be decoded or fails invariants.
    case corrupt(String)
    /// The file exists but its bytes cannot be read (permissions, data protection).
    case unreadable(String)
}

public enum StoreError: Error, Equatable {
    case missing
    case unsupportedSchema(Int)
    case corrupt(String)
    case unreadable(String)
    case writeFailed(String)
    case replaceFailed(String)
    case verificationMismatch(StoreCommitStage)
    case interrupted(StoreCommitStage)
}

public enum StoreCommitStage: String, Equatable, Sendable {
    case temporaryFile
    case beforeReplace
    case afterReplace
    case finalFile
}

/// Injectable byte writer so tests can fail a write at a chosen stage.
public protocol StoreFileWriter {
    func write(_ data: Data, to url: URL) throws
}

public struct DefaultStoreFileWriter: StoreFileWriter {
    public let attributes: [FileAttributeKey: Any]

    public init(attributes: [FileAttributeKey: Any] = [:]) {
        self.attributes = attributes
    }

    public func write(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes.isEmpty ? nil : attributes) else {
            throw StoreError.writeFailed("createFile")
        }
        try DurableFileWriter.write(data, toExistingFile: url)
    }
}

/// POSIX write + fsync that reports failures as errors. `FileHandle.write(_:)` and
/// `synchronizeFile()` raise Objective-C exceptions on ENOSPC/EIO, which would
/// terminate the process instead of reaching the recovery screen.
public enum DurableFileWriter {
    public static func write(_ data: Data, toExistingFile url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_TRUNC | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError.writeFailed("open: \(String(cString: strerror(errno)))") }
        defer { close(descriptor) }
        var offset = 0
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw StoreError.writeFailed("write: \(String(cString: strerror(errno)))")
                }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw StoreError.writeFailed("fsync: \(String(cString: strerror(errno)))") }
    }
}

/// Hooks fired inside the commit so tests can simulate a crash at each point.
public struct StoreCommitHooks {
    public var onStage: (StoreCommitStage) throws -> Void

    public init(onStage: @escaping (StoreCommitStage) throws -> Void = { _ in }) {
        self.onStage = onStage
    }
}

public protocol AppStateStore: AnyObject {
    func load() throws -> AppState
    @discardableResult
    func modify(_ change: (inout AppState) throws -> Void) throws -> AppState
}

/// The single write owner for the schema 2 document.
///
/// Commit order: validate in memory → write a temporary file next to the target
/// → decode the temporary file and compare → atomically rename over the target
/// → decode the final file and compare. A failure at any point leaves the
/// previous file untouched. Read→modify→commit is serialized per file path
/// across all instances in the process.
public final class FileAppStateStore: AppStateStore {
    public let fileURL: URL
    private let fileManager: FileManager
    private let writer: StoreFileWriter
    private let hooks: StoreCommitHooks
    private let directoryAttributes: [FileAttributeKey: Any]?

    private static let registryLock = NSLock()
    private static var locks: [String: NSRecursiveLock] = [:]

    private static func lock(for url: URL) -> NSRecursiveLock {
        let key = url.standardizedFileURL.path
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[key] { return existing }
        let lock = NSRecursiveLock()
        locks[key] = lock
        return lock
    }

    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        writer: StoreFileWriter = DefaultStoreFileWriter(),
        directoryAttributes: [FileAttributeKey: Any]? = nil,
        hooks: StoreCommitHooks = StoreCommitHooks()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.writer = writer
        self.directoryAttributes = directoryAttributes
        self.hooks = hooks
    }

    // MARK: Inspection

    public static func inspect(fileURL: URL, fileManager: FileManager = .default) -> StoreInspection {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { return .unreadable(String(describing: error)) }
        return inspect(data: data)
    }

    static func inspect(data: Data) -> StoreInspection {
        struct VersionOnly: Decodable { let schemaVersion: Int }
        struct Schema1: Decodable { let schemaVersion: Int; let logs: [DailyLog] }
        let decoder = JSONDecoder()
        let version: Int
        do { version = try decoder.decode(VersionOnly.self, from: data).schemaVersion }
        catch { return .corrupt(String(describing: error)) }
        switch version {
        case AppState.currentSchemaVersion:
            do { return .ready(try decoder.decode(AppState.self, from: data)) }
            catch { return .corrupt(String(describing: error)) }
        case 1:
            do {
                let file = try decoder.decode(Schema1.self, from: data)
                var days = Set<CalendarDay>()
                for log in file.logs where !days.insert(log.day).inserted {
                    return .corrupt("duplicate day \(log.day.iso8601) in schema 1 file")
                }
                return .legacySchema1(logs: file.logs)
            } catch { return .corrupt(String(describing: error)) }
        default:
            return .unsupportedSchema(version)
        }
    }

    public func inspect() -> StoreInspection {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        return Self.inspect(fileURL: fileURL, fileManager: fileManager)
    }

    // MARK: Reading

    public func load() throws -> AppState {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        return try loadLocked()
    }

    private func loadLocked() throws -> AppState {
        switch Self.inspect(fileURL: fileURL, fileManager: fileManager) {
        case .ready(let state): return state
        case .missing: throw StoreError.missing
        case .legacySchema1: throw StoreError.unsupportedSchema(1)
        case .unsupportedSchema(let version): throw StoreError.unsupportedSchema(version)
        case .corrupt(let reason): throw StoreError.corrupt(reason)
        case .unreadable(let reason): throw StoreError.unreadable(reason)
        }
    }

    // MARK: Writing

    /// Writes `state` as the whole document. Used for the initial commit and
    /// for full replacements produced by migration.
    public func commit(_ state: AppState) throws {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        try commitLocked(state)
    }

    @discardableResult
    public func modify(_ change: (inout AppState) throws -> Void) throws -> AppState {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        var state = try loadLocked()
        try change(&state)
        try state.validate()
        try commitLocked(state)
        return state
    }

    private func commitLocked(_ state: AppState) throws {
        try state.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)

        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: directoryAttributes
            )
        }
        removeStaleTemporaryFiles(in: directory)
        let temporaryURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do { try writer.write(data, to: temporaryURL) }
        catch let error as StoreError { throw error }
        catch { throw StoreError.writeFailed(String(describing: error)) }
        try fire(.temporaryFile)

        let reread: AppState
        do { reread = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: temporaryURL)) }
        catch { throw StoreError.verificationMismatch(.temporaryFile) }
        guard reread == state else { throw StoreError.verificationMismatch(.temporaryFile) }

        try fire(.beforeReplace)
        let result = rename(temporaryURL.path, fileURL.path)
        guard result == 0 else {
            throw StoreError.replaceFailed(String(cString: strerror(errno)))
        }
        try fire(.afterReplace)

        let final: AppState
        do { final = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: fileURL)) }
        catch { throw StoreError.verificationMismatch(.finalFile) }
        guard final == state else { throw StoreError.verificationMismatch(.finalFile) }
    }

    /// A process killed between the temporary write and the rename leaves a
    /// dotfile behind. It is never read. Only files older than an hour are
    /// removed so another process mid-commit is not disturbed.
    static let staleTemporaryFileAge: TimeInterval = 3600

    private func removeStaleTemporaryFiles(in directory: URL) {
        let prefix = ".\(fileURL.lastPathComponent).tmp-"
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            let url = directory.appendingPathComponent(name)
            guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  Date().timeIntervalSince(modified) > Self.staleTemporaryFileAge else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func fire(_ stage: StoreCommitStage) throws {
        do { try hooks.onStage(stage) }
        catch let error as StoreError { throw error }
        catch { throw StoreError.interrupted(stage) }
    }
}
