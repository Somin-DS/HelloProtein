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
    /// A previous commit replaced the file but its result was never confirmed.
    /// Writes stay refused until a successful `load()` (or `inspect()` that
    /// finds a ready file) re-establishes the state. Reported as
    /// `StoreCommitError.indeterminate`: the on-disk state is unknown, so the
    /// caller must re-read before deciding anything.
    case previousCommitUnconfirmed(operationID: String?)
}

/// Result contract of a commit. The two cases must never be conflated: after
/// `notCommitted` the previous file is intact and the same operation can simply
/// be retried; after `indeterminate` the replacement happened (or may have) and
/// the caller must re-read the store before deciding anything.
public enum StoreCommitError: Error, Equatable {
    /// Failed before the rename. The previous file is untouched.
    case notCommitted(StoreError)
    /// The rename succeeded (or was interrupted right after it) but the final
    /// file could not be confirmed. The file is never rolled back.
    case indeterminate(StoreError)

    public var underlying: StoreError {
        switch self {
        case .notCommitted(let error), .indeterminate(let error): return error
        }
    }
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
    /// Throws `StoreError`. A successful load confirms the on-disk state and
    /// lifts the write block left by an indeterminate commit.
    func load() throws -> AppState
    /// Throws `StoreCommitError` for storage failures; errors thrown by
    /// `change` or by validation are rethrown unchanged. `operationID` is
    /// stored in the document so a retry can tell whether it already landed.
    @discardableResult
    func modify(operationID: String?, _ change: (inout AppState) throws -> Void) throws -> AppState
    /// Operation ID of the commit whose result is still unconfirmed, if any.
    var unconfirmedOperationID: String? { get }
    /// True while a commit's outcome is unknown; `modify`/`commit` are refused.
    var hasUnconfirmedCommit: Bool { get }
}

public extension AppStateStore {
    @discardableResult
    func modify(_ change: (inout AppState) throws -> Void) throws -> AppState {
        try modify(operationID: nil, change)
    }
}

/// The single write owner for the schema 2 document.
///
/// Commit order: validate in memory → write a temporary file next to the target
/// → decode the temporary file and compare → atomically rename over the target
/// → decode the final file and compare.
///
/// Failure boundary: anything before the rename leaves the previous file
/// untouched and is reported as `StoreCommitError.notCommitted`. Once the
/// rename returned success the new document is on disk; a failure after that
/// is `StoreCommitError.indeterminate`, the file is not rolled back, and every
/// store on that path refuses further writes until a `load()` succeeds (or an
/// `inspect()` finds a ready file). Read→modify→commit and the write block are
/// both kept per file path, shared by all instances in the process.
public final class FileAppStateStore: AppStateStore {
    public let fileURL: URL
    private let fileManager: FileManager
    private let writer: StoreFileWriter
    private let hooks: StoreCommitHooks
    private let directoryAttributes: [FileAttributeKey: Any]?
    private let shared: PathState

    public var hasUnconfirmedCommit: Bool { shared.unconfirmed().blocked }

    public var unconfirmedOperationID: String? {
        let unconfirmed = shared.unconfirmed()
        return unconfirmed.blocked ? unconfirmed.operationID : nil
    }

    /// Process-wide state of one file path: the commit lock and the "outcome
    /// unknown" flag. The flag has its own short lock so the UI can read it
    /// while a commit (fsync included) is running.
    private final class PathState {
        let commitLock = NSRecursiveLock()
        private let flagLock = NSLock()
        private var blocked = false
        private var operationID: String?

        func unconfirmed() -> (blocked: Bool, operationID: String?) {
            flagLock.lock()
            defer { flagLock.unlock() }
            return (blocked, operationID)
        }

        func setUnconfirmed(_ blocked: Bool, operationID: String?) {
            flagLock.lock()
            defer { flagLock.unlock() }
            self.blocked = blocked
            self.operationID = blocked ? operationID : nil
        }
    }

    private static let registryLock = NSLock()
    private static var states: [String: PathState] = [:]

    private static func state(for url: URL) -> PathState {
        let key = url.standardizedFileURL.path
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = states[key] { return existing }
        let state = PathState()
        states[key] = state
        return state
    }

    private static func lock(for url: URL) -> NSRecursiveLock { state(for: url).commitLock }

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
        self.shared = Self.state(for: fileURL)
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

    /// A `.ready` result confirms the on-disk state exactly as `load()` does
    /// and lifts the write block.
    public func inspect() -> StoreInspection {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        return inspectLocked()
    }

    private func inspectLocked() -> StoreInspection {
        let inspection = Self.inspect(fileURL: fileURL, fileManager: fileManager)
        if case .ready = inspection {
            // The on-disk state is known again; writes may resume.
            shared.setUnconfirmed(false, operationID: nil)
        }
        return inspection
    }

    // MARK: Reading

    public func load() throws -> AppState {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        return try loadLocked()
    }

    private func loadLocked() throws -> AppState {
        switch inspectLocked() {
        case .ready(let state):
            return state
        case .missing: throw StoreError.missing
        case .legacySchema1: throw StoreError.unsupportedSchema(1)
        case .unsupportedSchema(let version): throw StoreError.unsupportedSchema(version)
        case .corrupt(let reason): throw StoreError.corrupt(reason)
        case .unreadable(let reason): throw StoreError.unreadable(reason)
        }
    }

    // MARK: Writing

    /// Writes `state` as the whole document. Used for the initial commit and
    /// for full replacements produced by migration. Throws `StoreCommitError`
    /// for storage failures; validation errors are rethrown unchanged.
    public func commit(_ state: AppState) throws {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        try state.validate()
        try commitLocked(state, operationID: nil)
    }

    @discardableResult
    public func modify(operationID: String?, _ change: (inout AppState) throws -> Void) throws -> AppState {
        let lock = Self.lock(for: fileURL)
        lock.lock()
        defer { lock.unlock() }
        try refuseIfUnconfirmed()
        var state: AppState
        do { state = try loadLocked() }
        catch let error as StoreError { throw StoreCommitError.notCommitted(error) }
        try change(&state)
        state.lastOperationID = operationID
        try state.validate()
        try commitLocked(state, operationID: operationID)
        return state
    }

    /// The state on disk is unknown, so this is reported as `indeterminate`
    /// even though the new operation itself was never attempted: "retry the
    /// same operation" would be the wrong advice until a read has succeeded.
    private func refuseIfUnconfirmed() throws {
        let unconfirmed = shared.unconfirmed()
        if unconfirmed.blocked {
            throw StoreCommitError.indeterminate(.previousCommitUnconfirmed(operationID: unconfirmed.operationID))
        }
    }

    private func commitLocked(_ state: AppState, operationID: String?) throws {
        try refuseIfUnconfirmed()
        let temporaryURL: URL
        do {
            temporaryURL = try prepareTemporaryFile(for: state)
        } catch let error as StoreError {
            throw StoreCommitError.notCommitted(error)
        } catch {
            throw StoreCommitError.notCommitted(.writeFailed(String(describing: error)))
        }
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do { try fire(.beforeReplace) }
        catch let error as StoreError { throw StoreCommitError.notCommitted(error) }
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            throw StoreCommitError.notCommitted(.replaceFailed(String(cString: strerror(errno))))
        }
        // From here on the new document is on disk. Never roll it back: a later
        // successful change could be lost with it.
        shared.setUnconfirmed(true, operationID: operationID)
        do {
            try fire(.afterReplace)
            let final: AppState
            do { final = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: fileURL)) }
            catch { throw StoreError.verificationMismatch(.finalFile) }
            guard final == state else { throw StoreError.verificationMismatch(.finalFile) }
        } catch let error as StoreError {
            throw StoreCommitError.indeterminate(error)
        }
        shared.setUnconfirmed(false, operationID: nil)
    }

    /// Everything that can fail without touching the target file.
    private func prepareTemporaryFile(for state: AppState) throws -> URL {
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
        do {
            do { try writer.write(data, to: temporaryURL) }
            catch let error as StoreError { throw error }
            catch { throw StoreError.writeFailed(String(describing: error)) }
            try fire(.temporaryFile)

            let reread: AppState
            do { reread = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: temporaryURL)) }
            catch { throw StoreError.verificationMismatch(.temporaryFile) }
            guard reread == state else { throw StoreError.verificationMismatch(.temporaryFile) }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
        return temporaryURL
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
