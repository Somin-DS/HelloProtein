import Foundation
import HelloProteinCore

/// Points at which a test (or a debug launch argument) can stop the process.
/// After a stop at any point, the next launch must end in either the previous
/// good state or the completed new state, never a partial one.
public enum InterruptionPoint: String, CaseIterable, Equatable, Codable {
    case beforeBackup
    case afterBackup
    case afterMapping
    case afterTemporaryWrite
    case beforeReplace
    case afterReplace
    case beforeFirstScreen
}

public struct MigrationInterrupted: Error, Equatable {
    public let point: InterruptionPoint
    public init(point: InterruptionPoint) { self.point = point }
}

public struct LegacyProbe: Equatable {
    public let realmFilePresent: Bool
    public let presentDefaultsKeys: [String]

    public init(realmFilePresent: Bool, presentDefaultsKeys: [String]) {
        self.realmFilePresent = realmFilePresent
        self.presentDefaultsKeys = presentDefaultsKeys
    }

    public var hasAnyEvidence: Bool { realmFilePresent || !presentDefaultsKeys.isEmpty }
}

/// The iOS layer implements this with Realm and UserDefaults. `probe` must not
/// create files; `capture` must not modify the original.
public protocol LegacySourceGateway {
    func probe() throws -> LegacyProbe
    func capture() throws -> LegacyCapture
}

public struct BackupRecord: Codable, Equatable {
    public let fingerprint: String
    public let capturedAt: String
    public let capture: LegacyCapture

    public init(fingerprint: String, capturedAt: String, capture: LegacyCapture) {
        self.fingerprint = fingerprint
        self.capturedAt = capturedAt
        self.capture = capture
    }
}

/// Secondary evidence written after a successful commit. It is never the
/// criterion for "migration complete"; the store file is. It only lets a later
/// launch tell "store deleted after completion" from "fresh install".
public struct CompletionEvidence: Codable, Equatable {
    public let migration: MigrationRecord
    public let writtenAt: String

    public init(migration: MigrationRecord, writtenAt: String) {
        self.migration = migration
        self.writtenAt = writtenAt
    }
}

public protocol MigrationEvidenceStore {
    func latestBackup() throws -> BackupRecord?
    func writeBackup(_ record: BackupRecord) throws
    func completionEvidence() throws -> CompletionEvidence?
    func writeCompletionEvidence(_ evidence: CompletionEvidence) throws
    func preserveSchema1File(at url: URL) throws
}

public enum RecoveryKind: String, Codable, Equatable {
    case storeCorrupt
    case storeUnsupportedSchema
    case storeUnreadable
    case storeLost
    case schema1Conflict
    case legacyCaptureFailed
    case backupFailed
    case unexpectedDefaultsType
    case legacyInvalid
    case legacyUnrepresentable
    case commitFailed
    case verificationFailed
    case interrupted
}

public struct RecoveryState: Equatable {
    public let kind: RecoveryKind
    public let detail: String
    /// The coordinator never writes to the old Realm or UserDefaults.
    public let originalPreserved: Bool
    public let backupAvailable: Bool
    public let canRetry: Bool

    public init(kind: RecoveryKind, detail: String, originalPreserved: Bool = true, backupAvailable: Bool, canRetry: Bool) {
        self.kind = kind
        self.detail = detail
        self.originalPreserved = originalPreserved
        self.backupAvailable = backupAvailable
        self.canRetry = canRetry
    }
}

public enum LaunchOutcome: Equatable {
    case ready(AppState)
    case recovery(RecoveryState)
}

public struct MigrationEnvironment {
    public var today: CalendarDay
    public var now: () -> Date
    public var migrationVersion: Int
    public var interrupt: (InterruptionPoint) throws -> Void

    public init(
        today: CalendarDay,
        now: @escaping () -> Date = Date.init,
        migrationVersion: Int = MigrationEnvironment.currentMigrationVersion,
        interrupt: @escaping (InterruptionPoint) throws -> Void = { _ in }
    ) {
        self.today = today
        self.now = now
        self.migrationVersion = migrationVersion
        self.interrupt = interrupt
    }

    public static let currentMigrationVersion = 1
}

/// Decides what the app should show at launch and performs the one-time
/// migration when needed. Safe to construct and run again after any failure.
public final class MigrationCoordinator {
    public enum Source: Equatable { case legacy, backup }

    private let store: FileAppStateStore
    private let legacy: LegacySourceGateway
    private let evidence: MigrationEvidenceStore
    private let environment: MigrationEnvironment

    public init(
        store: FileAppStateStore,
        legacy: LegacySourceGateway,
        evidence: MigrationEvidenceStore,
        environment: MigrationEnvironment
    ) {
        self.store = store
        self.legacy = legacy
        self.evidence = evidence
        self.environment = environment
    }

    public func launch() -> LaunchOutcome {
        switch store.inspect() {
        case .ready(let state):
            recordCompletionIfMissing(state.migration)
            return finish(state)
        case .corrupt(let reason):
            return .recovery(.init(kind: .storeCorrupt, detail: reason, backupAvailable: backupExists, canRetry: true))
        case .unsupportedSchema(let version):
            return .recovery(.init(kind: .storeUnsupportedSchema, detail: "schema \(version)", backupAvailable: backupExists, canRetry: false))
        case .unreadable(let reason):
            return .recovery(.init(kind: .storeUnreadable, detail: reason, backupAvailable: backupExists, canRetry: true))
        case .legacySchema1(let logs):
            return upgradeSchema1(logs)
        case .missing:
            return launchWithoutStore()
        }
    }

    private var backupExists: Bool { (try? evidence.latestBackup()) != nil }

    private func launchWithoutStore() -> LaunchOutcome {
        if let completion = try? evidence.completionEvidence() {
            return .recovery(.init(
                kind: .storeLost,
                detail: "completed \(completion.migration.completedAt), store file missing",
                backupAvailable: backupExists,
                canRetry: false
            ))
        }
        let probe: LegacyProbe
        do { probe = try legacy.probe() }
        catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: backupExists, canRetry: true)) }

        if probe.hasAnyEvidence {
            return migrate(from: .legacy)
        }
        if backupExists {
            return migrate(from: .backup)
        }
        return createFreshInstall()
    }

    private func createFreshInstall() -> LaunchOutcome {
        do {
            let state = try AppState.freshInstall(
                completedAt: LegacySnapshotBuilder.instantString(environment.now()),
                migrationVersion: environment.migrationVersion
            )
            try store.commit(state)
            let reloaded = try store.load()
            guard reloaded == state else {
                return .recovery(.init(kind: .verificationFailed, detail: "fresh install reload mismatch", backupAvailable: false, canRetry: true))
            }
            recordCompletionIfMissing(state.migration)
            return finish(state)
        } catch {
            return commitFailure(error)
        }
    }

    private func upgradeSchema1(_ logs: [DailyLog]) -> LaunchOutcome {
        let probe: LegacyProbe
        do { probe = try legacy.probe() }
        catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: backupExists, canRetry: true)) }
        if probe.hasAnyEvidence {
            // Both a prototype store and the old app's data exist. No verified
            // rule for overlapping days/IDs, so stop explicitly.
            return .recovery(.init(kind: .schema1Conflict, detail: "schema 1 store and legacy data both present", backupAvailable: backupExists, canRetry: false))
        }
        do {
            try evidence.preserveSchema1File(at: store.fileURL)
        } catch {
            return .recovery(.init(kind: .backupFailed, detail: String(describing: error), backupAvailable: false, canRetry: true))
        }
        do {
            let state = try AppState(
                logs: logs, favorites: [], searchHistory: [], settings: .freshInstall, goals: [],
                migration: MigrationRecord(
                    origin: .schema1Upgrade,
                    migrationVersion: environment.migrationVersion,
                    completedAt: LegacySnapshotBuilder.instantString(environment.now()),
                    sourceFingerprint: nil,
                    verification: nil
                )
            )
            try store.commit(state)
            guard try store.load() == state else {
                return .recovery(.init(kind: .verificationFailed, detail: "schema 1 upgrade reload mismatch", backupAvailable: true, canRetry: true))
            }
            recordCompletionIfMissing(state.migration)
            return finish(state)
        } catch {
            return commitFailure(error)
        }
    }

    private func migrate(from source: Source) -> LaunchOutcome {
        do { try environment.interrupt(.beforeBackup) }
        catch { return interrupted(.beforeBackup) }

        let capture: LegacyCapture
        let fingerprint: String
        switch source {
        case .legacy:
            do { capture = try legacy.capture() }
            catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: backupExists, canRetry: true)) }
            do { fingerprint = try LegacyFingerprint.sha256Hex(of: capture) }
            catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: "fingerprint: \(error)", backupAvailable: backupExists, canRetry: true)) }
            do {
                let existing = try evidence.latestBackup()
                if existing?.fingerprint != fingerprint {
                    try evidence.writeBackup(BackupRecord(
                        fingerprint: fingerprint,
                        capturedAt: LegacySnapshotBuilder.instantString(environment.now()),
                        capture: capture
                    ))
                }
                guard try evidence.latestBackup()?.fingerprint == fingerprint else {
                    throw StoreError.verificationMismatch(.finalFile)
                }
            } catch {
                return .recovery(.init(kind: .backupFailed, detail: String(describing: error), backupAvailable: false, canRetry: true))
            }
        case .backup:
            do {
                guard let record = try evidence.latestBackup() else {
                    return .recovery(.init(kind: .legacyCaptureFailed, detail: "backup vanished", backupAvailable: false, canRetry: true))
                }
                capture = record.capture
                fingerprint = record.fingerprint
                guard try LegacyFingerprint.sha256Hex(of: capture) == fingerprint else {
                    return .recovery(.init(kind: .legacyCaptureFailed, detail: "backup fingerprint mismatch", backupAvailable: true, canRetry: false))
                }
            } catch {
                return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: false, canRetry: true))
            }
        }

        do { try environment.interrupt(.afterBackup) }
        catch { return interrupted(.afterBackup) }

        guard capture.typeIssues.isEmpty else {
            let keys = capture.typeIssues.map(\.key).joined(separator: ",")
            return .recovery(.init(kind: .unexpectedDefaultsType, detail: keys, backupAvailable: true, canRetry: false))
        }

        let plan: MigrationPlan
        do { plan = try LegacyMigration.prepare(LegacySnapshotBuilder.build(from: capture.raw)) }
        catch { return .recovery(.init(kind: .legacyInvalid, detail: String(describing: error), backupAvailable: true, canRetry: false)) }

        let state: AppState
        do {
            state = try LegacyStateMapper.map(plan, context: .init(
                migratedOn: environment.today,
                completedAt: LegacySnapshotBuilder.instantString(environment.now()),
                migrationVersion: environment.migrationVersion,
                sourceFingerprint: fingerprint
            ))
        } catch {
            return .recovery(.init(kind: .legacyUnrepresentable, detail: String(describing: error), backupAvailable: true, canRetry: false))
        }

        do { try environment.interrupt(.afterMapping) }
        catch { return interrupted(.afterMapping) }

        do { try store.commit(state) }
        catch { return commitFailure(error) }

        do {
            let reloaded = try store.load()
            guard reloaded == state else {
                return .recovery(.init(kind: .verificationFailed, detail: "reloaded state differs", backupAvailable: true, canRetry: true))
            }
            let problems = LegacyStateMapper.verify(reloaded, against: plan)
            guard problems.isEmpty else {
                return .recovery(.init(kind: .verificationFailed, detail: problems.joined(separator: "; "), backupAvailable: true, canRetry: true))
            }
        } catch {
            return .recovery(.init(kind: .verificationFailed, detail: String(describing: error), backupAvailable: true, canRetry: true))
        }

        recordCompletionIfMissing(state.migration)
        return finish(state)
    }

    private func finish(_ state: AppState) -> LaunchOutcome {
        do { try environment.interrupt(.beforeFirstScreen) }
        catch { return interrupted(.beforeFirstScreen) }
        return .ready(state)
    }

    private func recordCompletionIfMissing(_ record: MigrationRecord) {
        guard (try? evidence.completionEvidence()) == nil else { return }
        try? evidence.writeCompletionEvidence(CompletionEvidence(
            migration: record,
            writtenAt: LegacySnapshotBuilder.instantString(environment.now())
        ))
    }

    private func commitFailure(_ error: Error) -> LaunchOutcome {
        if case StoreError.interrupted(let stage) = error {
            return .recovery(.init(kind: .interrupted, detail: stage.rawValue, backupAvailable: backupExists, canRetry: true))
        }
        return .recovery(.init(kind: .commitFailed, detail: String(describing: error), backupAvailable: backupExists, canRetry: true))
    }

    private func interrupted(_ point: InterruptionPoint) -> LaunchOutcome {
        .recovery(.init(kind: .interrupted, detail: point.rawValue, backupAvailable: backupExists, canRetry: true))
    }
}

/// JSON files in an app-private persistent directory. Backups are written to a
/// temporary file and renamed, so a half-written backup is never read back.
public final class FileMigrationEvidenceStore: MigrationEvidenceStore {
    public let directory: URL
    private let fileManager: FileManager
    private let attributes: [FileAttributeKey: Any]?

    public var backupURL: URL { directory.appendingPathComponent("legacy-capture.json") }
    public var completionURL: URL { directory.appendingPathComponent("migration-completed.json") }
    public var schema1BackupURL: URL { directory.appendingPathComponent("schema1-app-state.json") }

    public init(directory: URL, fileManager: FileManager = .default, attributes: [FileAttributeKey: Any]? = nil) {
        self.directory = directory
        self.fileManager = fileManager
        self.attributes = attributes
    }

    public func latestBackup() throws -> BackupRecord? {
        guard fileManager.fileExists(atPath: backupURL.path) else { return nil }
        return try decoder().decode(BackupRecord.self, from: Data(contentsOf: backupURL))
    }

    public func writeBackup(_ record: BackupRecord) throws {
        try writeAtomically(try encoder().encode(record), to: backupURL)
    }

    public func completionEvidence() throws -> CompletionEvidence? {
        guard fileManager.fileExists(atPath: completionURL.path) else { return nil }
        return try JSONDecoder().decode(CompletionEvidence.self, from: Data(contentsOf: completionURL))
    }

    public func writeCompletionEvidence(_ evidence: CompletionEvidence) throws {
        try writeAtomically(try encoder().encode(evidence), to: completionURL)
    }

    public func preserveSchema1File(at url: URL) throws {
        try ensureDirectory()
        if fileManager.fileExists(atPath: schema1BackupURL.path) { return }
        try fileManager.copyItem(at: url, to: schema1BackupURL)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(LegacySnapshotBuilder.instantString(date))
        }
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = LegacySnapshotBuilder.instant(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad instant \(text)"))
            }
            return date
        }
        return decoder
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        try ensureDirectory()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        guard fileManager.createFile(atPath: temporary.path, contents: nil, attributes: attributes) else {
            throw StoreError.writeFailed("createFile \(temporary.lastPathComponent)")
        }
        try DurableFileWriter.write(data, toExistingFile: temporary)
        guard rename(temporary.path, url.path) == 0 else {
            throw StoreError.replaceFailed(String(cString: strerror(errno)))
        }
    }
}
