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
    public static let currentFormatVersion = 1

    /// Files written before this field existed decode as version 1.
    public let evidenceFormatVersion: Int
    public let fingerprint: String
    public let capturedAt: String
    public let capture: LegacyCapture

    public init(fingerprint: String, capturedAt: String, capture: LegacyCapture, evidenceFormatVersion: Int = BackupRecord.currentFormatVersion) {
        self.evidenceFormatVersion = evidenceFormatVersion
        self.fingerprint = fingerprint
        self.capturedAt = capturedAt
        self.capture = capture
    }

    private enum CodingKeys: String, CodingKey { case evidenceFormatVersion, fingerprint, capturedAt, capture }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evidenceFormatVersion = try container.decodeIfPresent(Int.self, forKey: .evidenceFormatVersion) ?? 1
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        capturedAt = try container.decode(String.self, forKey: .capturedAt)
        capture = try container.decode(LegacyCapture.self, forKey: .capture)
    }
}

/// Secondary evidence written after a successful commit. It is never the
/// criterion for "migration complete"; the store file is. It only lets a later
/// launch tell "store deleted after completion" from "fresh install".
public struct CompletionEvidence: Codable, Equatable {
    public static let currentFormatVersion = 1

    public let evidenceFormatVersion: Int
    public let migration: MigrationRecord
    public let writtenAt: String

    public init(migration: MigrationRecord, writtenAt: String, evidenceFormatVersion: Int = CompletionEvidence.currentFormatVersion) {
        self.evidenceFormatVersion = evidenceFormatVersion
        self.migration = migration
        self.writtenAt = writtenAt
    }

    private enum CodingKeys: String, CodingKey { case evidenceFormatVersion, migration, writtenAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evidenceFormatVersion = try container.decodeIfPresent(Int.self, forKey: .evidenceFormatVersion) ?? 1
        migration = try container.decode(MigrationRecord.self, forKey: .migration)
        writtenAt = try container.decode(String.self, forKey: .writtenAt)
    }
}

/// Result of looking at one evidence file. Only `missing` means the file is
/// really absent; every other non-valid case means "something is there that
/// must not be overwritten or reasoned away".
public enum EvidenceInspection<Value: Equatable>: Equatable {
    case missing
    case valid(Value)
    /// Exists but cannot be decoded or fails its own checks.
    case corrupt(String)
    /// Exists but its bytes cannot be read (permissions, data protection).
    case unreadable(String)
    /// Exists and declares a format newer than this build understands.
    case unsupported(Int)

    public var value: Value? {
        if case .valid(let value) = self { return value }
        return nil
    }

    public var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }
}

public struct EvidenceUnusable: Error, Equatable {
    public enum Reason: Equatable { case corrupt(String), unreadable(String), unsupported(Int) }
    public let reason: Reason
}

/// The original schema 2 store file, byte for byte, kept next to the
/// promoted file. It is never rewritten: a second launch that finds it
/// verifies the digest instead.
public struct SchemaBackup: Equatable {
    public let data: Data
    public let sha256: String

    public init(data: Data) {
        self.data = data
        self.sha256 = LegacyFingerprint.sha256Hex(of: data)
    }
}

/// Written after a schema promotion committed and was read back. Secondary
/// evidence only: a valid current-schema store is opened with or without it.
/// Its operation ID identifies the promotion and is never a user save ID.
public struct SchemaPromotionEvidence: Codable, Equatable {
    public static let currentFormatVersion = 1

    public let evidenceFormatVersion: Int
    public let fromSchemaVersion: Int
    public let toSchemaVersion: Int
    /// Digest and size of the backed-up original file.
    public let backupSHA256: String
    public let backupByteCount: Int
    public let promotedAt: String
    public let operationID: String

    public init(fromSchemaVersion: Int, toSchemaVersion: Int, backupSHA256: String, backupByteCount: Int,
                promotedAt: String, operationID: String, evidenceFormatVersion: Int = SchemaPromotionEvidence.currentFormatVersion) {
        self.evidenceFormatVersion = evidenceFormatVersion
        self.fromSchemaVersion = fromSchemaVersion
        self.toSchemaVersion = toSchemaVersion
        self.backupSHA256 = backupSHA256
        self.backupByteCount = backupByteCount
        self.promotedAt = promotedAt
        self.operationID = operationID
    }
}

public protocol MigrationEvidenceStore {
    func inspectBackup() -> EvidenceInspection<BackupRecord>
    func writeBackup(_ record: BackupRecord) throws
    func inspectCompletion() -> EvidenceInspection<CompletionEvidence>
    func writeCompletionEvidence(_ evidence: CompletionEvidence) throws
    func preserveSchema1File(at url: URL) throws
    /// The schema 2 original kept for the schema 3 promotion. `corrupt` when
    /// the bytes are present but are not a valid schema 2 document.
    func inspectSchema2Backup() -> EvidenceInspection<SchemaBackup>
    /// Writes the original bytes once; an existing file is never replaced.
    func writeSchema2Backup(_ data: Data) throws
    func inspectSchemaPromotion() -> EvidenceInspection<SchemaPromotionEvidence>
    func writeSchemaPromotionEvidence(_ evidence: SchemaPromotionEvidence) throws
}

public extension MigrationEvidenceStore {
    /// nil only when the file is absent; any unusable file throws `EvidenceUnusable`.
    func latestBackup() throws -> BackupRecord? { try Self.unwrap(inspectBackup()) }
    func completionEvidence() throws -> CompletionEvidence? { try Self.unwrap(inspectCompletion()) }

    private static func unwrap<T>(_ inspection: EvidenceInspection<T>) throws -> T? {
        switch inspection {
        case .missing: return nil
        case .valid(let value): return value
        case .corrupt(let reason): throw EvidenceUnusable(reason: .corrupt(reason))
        case .unreadable(let reason): throw EvidenceUnusable(reason: .unreadable(reason))
        case .unsupported(let version): throw EvidenceUnusable(reason: .unsupported(version))
        }
    }
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
    /// A completion marker or backup exists but cannot be decoded. Nothing is
    /// re-imported, created or overwritten while it is in this state.
    case evidenceCorrupt
    /// A completion marker or backup exists but cannot be read.
    case evidenceUnreadable
    /// A completion marker or backup declares a newer format than this build.
    case evidenceUnsupported
    /// The schema 2 original could not be backed up (or the backup could not
    /// be read back), so the schema 3 promotion did not start.
    case schemaBackupFailed
    /// A schema 2 backup exists but does not match the schema 2 file that is
    /// about to be promoted. Nothing is overwritten or promoted.
    case schemaBackupMismatch
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
            // Policy: a readable store is the truth. Unusable secondary evidence
            // next to it neither blocks the user nor gets overwritten; only a
            // genuinely missing marker is (re)written.
            recordCompletionIfMissing(state.migration)
            recordPromotionIfMissing(state)
            return finish(state)
        case .corrupt(let reason):
            return .recovery(.init(kind: .storeCorrupt, detail: reason, backupAvailable: backupAvailable, canRetry: true))
        case .unsupportedSchema(let version):
            return .recovery(.init(kind: .storeUnsupportedSchema, detail: "schema \(version)", backupAvailable: backupAvailable, canRetry: false))
        case .unreadable(let reason):
            return .recovery(.init(kind: .storeUnreadable, detail: reason, backupAvailable: backupAvailable, canRetry: true))
        case .legacySchema1(let logs):
            return upgradeSchema1(logs)
        case .legacySchema2(let state):
            return promoteSchema2(state)
        case .missing:
            return launchWithoutStore()
        }
    }

    /// True only for a backup that exists, decodes *and* hashes to its own fingerprint.
    private var backupAvailable: Bool { inspectBackup().value != nil }

    /// A backup is trusted only when its contents still hash to the fingerprint
    /// it carries. Decoding alone is not enough: an edited body under an old
    /// fingerprint would otherwise be accepted as a valid backup during a
    /// legacy migration and only fail later, when it is actually needed.
    private func inspectBackup() -> EvidenceInspection<BackupRecord> {
        let inspection = evidence.inspectBackup()
        guard case .valid(let record) = inspection else { return inspection }
        do {
            let actual = try LegacyFingerprint.sha256Hex(of: record.capture)
            guard actual == record.fingerprint else {
                return .corrupt("fingerprint mismatch: file says \(record.fingerprint), contents hash to \(actual)")
            }
        } catch {
            return .corrupt("fingerprint: \(error)")
        }
        return inspection
    }

    /// Maps an unusable evidence file to the recovery state that stops the
    /// launch. `backupAvailable` is the real inspection result unless the
    /// unusable file *is* the backup: a damaged backup never counts as
    /// available, but a damaged marker must not hide a valid backup either.
    private func evidenceProblem<T>(_ inspection: EvidenceInspection<T>, label: String) -> RecoveryState? {
        let backupAvailable = T.self == BackupRecord.self ? false : self.backupAvailable
        switch inspection {
        case .missing, .valid:
            return nil
        case .corrupt(let reason):
            return .init(kind: .evidenceCorrupt, detail: "\(label): \(reason)", backupAvailable: backupAvailable, canRetry: false)
        case .unreadable(let reason):
            return .init(kind: .evidenceUnreadable, detail: "\(label): \(reason)", backupAvailable: backupAvailable, canRetry: true)
        case .unsupported(let version):
            return .init(kind: .evidenceUnsupported, detail: "\(label): format \(version)", backupAvailable: backupAvailable, canRetry: false)
        }
    }

    private func launchWithoutStore() -> LaunchOutcome {
        // Only a file that is really absent lets the decision continue. A
        // marker or backup that exists but cannot be trusted stops here, before
        // the old source is probed, so nothing is re-imported or created.
        let completion = evidence.inspectCompletion()
        if let problem = evidenceProblem(completion, label: "completion") { return .recovery(problem) }
        if let completion = completion.value {
            return .recovery(.init(
                kind: .storeLost,
                detail: "completed \(completion.migration.completedAt), store file missing",
                backupAvailable: backupAvailable,
                canRetry: false
            ))
        }
        // Evidence of a schema promotion is evidence that a store existed:
        // a missing file next to it is a loss, never a fresh install.
        let promotion = evidence.inspectSchemaPromotion()
        if let problem = evidenceProblem(promotion, label: "schemaPromotion") { return .recovery(problem) }
        if let promotion = promotion.value {
            return .recovery(.init(
                kind: .storeLost,
                detail: "schema \(promotion.toSchemaVersion) promoted \(promotion.promotedAt), store file missing",
                backupAvailable: backupAvailable,
                canRetry: false
            ))
        }
        let schemaBackup = evidence.inspectSchema2Backup()
        if let problem = evidenceProblem(schemaBackup, label: "schema2Backup") { return .recovery(problem) }
        if schemaBackup.value != nil {
            return .recovery(.init(
                kind: .storeLost,
                detail: "schema 2 backup present, store file missing",
                backupAvailable: backupAvailable,
                canRetry: false
            ))
        }
        let backup = inspectBackup()
        if let problem = evidenceProblem(backup, label: "backup") { return .recovery(problem) }

        let probe: LegacyProbe
        do { probe = try legacy.probe() }
        catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: backup.value != nil, canRetry: true)) }

        if probe.hasAnyEvidence {
            return migrate(from: .legacy)
        }
        if backup.value != nil {
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
        catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: backupAvailable, canRetry: true)) }
        if probe.hasAnyEvidence {
            // Both a prototype store and the old app's data exist. No verified
            // rule for overlapping days/IDs, so stop explicitly.
            return .recovery(.init(kind: .schema1Conflict, detail: "schema 1 store and legacy data both present", backupAvailable: backupAvailable, canRetry: false))
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

    /// Schema 2 → 3. The document was already read and validated under
    /// schema 2 rules; `state` is the same content in the current schema with
    /// every basis nil and the stored `lastOperationID` untouched. Order:
    /// back up the exact original bytes (or verify the existing backup
    /// matches them) → commit through the store's temp/verify/rename/reread
    /// path → reload and compare → write the promotion evidence. A failure
    /// before the rename leaves the schema 2 file for the next launch to
    /// retry; a failure after it is reported as unconfirmed and the next
    /// launch simply inspects the file.
    private func promoteSchema2(_ state: AppState) -> LaunchOutcome {
        do { try environment.interrupt(.beforeBackup) }
        catch { return interrupted(.beforeBackup) }

        let data: Data
        do { data = try Data(contentsOf: store.fileURL) }
        catch { return .recovery(.init(kind: .storeUnreadable, detail: String(describing: error), backupAvailable: backupAvailable, canRetry: true)) }
        // The bytes being backed up must be the document that was inspected.
        guard case .legacySchema2(let reread) = FileAppStateStore.inspect(data: data), reread == state else {
            return .recovery(.init(kind: .verificationFailed, detail: "store changed while reading schema 2", backupAvailable: backupAvailable, canRetry: true))
        }
        let digest = LegacyFingerprint.sha256Hex(of: data)

        // Promotion evidence left by an earlier run must describe this very
        // original; otherwise two different schema 2 files are involved and
        // nothing, not even a backup, is written.
        let promotion = evidence.inspectSchemaPromotion()
        if let problem = evidenceProblem(promotion, label: "schemaPromotion") { return .recovery(problem) }
        if let promotion = promotion.value, promotion.backupSHA256 != digest {
            return .recovery(.init(kind: .schemaBackupMismatch,
                                   detail: "promotion evidence \(promotion.backupSHA256) does not match store \(digest)",
                                   backupAvailable: backupAvailable, canRetry: false))
        }

        let existing = evidence.inspectSchema2Backup()
        if let problem = evidenceProblem(existing, label: "schema2Backup") { return .recovery(problem) }
        if let backup = existing.value {
            guard backup.sha256 == digest else {
                return .recovery(.init(kind: .schemaBackupMismatch,
                                       detail: "backup \(backup.sha256) does not match store \(digest)",
                                       backupAvailable: backupAvailable, canRetry: false))
            }
        } else {
            do { try evidence.writeSchema2Backup(data) }
            catch { return .recovery(.init(kind: .schemaBackupFailed, detail: String(describing: error), backupAvailable: backupAvailable, canRetry: true)) }
            guard evidence.inspectSchema2Backup().value?.sha256 == digest else {
                return .recovery(.init(kind: .schemaBackupFailed, detail: "schema 2 backup could not be read back", backupAvailable: backupAvailable, canRetry: true))
            }
        }

        do { try environment.interrupt(.afterBackup) }
        catch { return interrupted(.afterBackup) }

        do { try environment.interrupt(.afterMapping) }
        catch { return interrupted(.afterMapping) }

        do { try store.commit(state) }
        catch { return commitFailure(error) }

        do {
            guard try store.load() == state else {
                return .recovery(.init(kind: .verificationFailed, detail: "promoted state differs after reload", backupAvailable: backupAvailable, canRetry: true))
            }
        } catch {
            return .recovery(.init(kind: .verificationFailed, detail: String(describing: error), backupAvailable: backupAvailable, canRetry: true))
        }

        if promotion.isMissing {
            try? evidence.writeSchemaPromotionEvidence(SchemaPromotionEvidence(
                fromSchemaVersion: AppState.promotableSchemaVersion,
                toSchemaVersion: AppState.currentSchemaVersion,
                backupSHA256: digest,
                backupByteCount: data.count,
                promotedAt: LegacySnapshotBuilder.instantString(environment.now()),
                operationID: "schema-promotion-\(UUID().uuidString)"
            ))
        }
        recordCompletionIfMissing(state.migration)
        return finish(state)
    }

    private func migrate(from source: Source) -> LaunchOutcome {
        do { try environment.interrupt(.beforeBackup) }
        catch { return interrupted(.beforeBackup) }

        let capture: LegacyCapture
        let fingerprint: String
        switch source {
        case .legacy:
            do { capture = try legacy.capture() }
            catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: String(describing: error), backupAvailable: backupAvailable, canRetry: true)) }
            do { fingerprint = try LegacyFingerprint.sha256Hex(of: capture) }
            catch { return .recovery(.init(kind: .legacyCaptureFailed, detail: "fingerprint: \(error)", backupAvailable: backupAvailable, canRetry: true)) }
            // An existing backup is only ever replaced when it is valid and
            // describes a different source; an unusable one stops the launch.
            let existing = inspectBackup()
            if let problem = evidenceProblem(existing, label: "backup") { return .recovery(problem) }
            do {
                if existing.value?.fingerprint != fingerprint {
                    try evidence.writeBackup(BackupRecord(
                        fingerprint: fingerprint,
                        capturedAt: LegacySnapshotBuilder.instantString(environment.now()),
                        capture: capture
                    ))
                }
                guard inspectBackup().value?.fingerprint == fingerprint else {
                    throw StoreError.verificationMismatch(.finalFile)
                }
            } catch {
                return .recovery(.init(kind: .backupFailed, detail: String(describing: error), backupAvailable: false, canRetry: true))
            }
        case .backup:
            let inspection = inspectBackup()
            if let problem = evidenceProblem(inspection, label: "backup") { return .recovery(problem) }
            guard let record = inspection.value else {
                return .recovery(.init(kind: .legacyCaptureFailed, detail: "backup vanished", backupAvailable: false, canRetry: true))
            }
            capture = record.capture
            fingerprint = record.fingerprint
            do {
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

    /// Writes the marker only when it is genuinely absent. A corrupt,
    /// unreadable or unsupported marker is left exactly as it is: repairing
    /// secondary evidence is a separate, deliberate action, never a side effect
    /// of a launch.
    private func recordCompletionIfMissing(_ record: MigrationRecord) {
        guard evidence.inspectCompletion().isMissing else { return }
        try? evidence.writeCompletionEvidence(CompletionEvidence(
            migration: record,
            writtenAt: LegacySnapshotBuilder.instantString(environment.now())
        ))
    }

    /// A current-schema file next to a valid schema 2 backup but no promotion
    /// marker (the launch that promoted it was interrupted right after the
    /// rename): the marker is written from the backup's digest, but only when
    /// the backup decodes to exactly the content of the current file, so the
    /// marker never ties the store to some other original. Without that
    /// nothing is invented; a damaged marker is left as it is. `promotedAt`
    /// is the time of this reconstruction.
    private func recordPromotionIfMissing(_ state: AppState) {
        guard evidence.inspectSchemaPromotion().isMissing, let backup = evidence.inspectSchema2Backup().value,
              (try? AppState.decodeSchema2(backup.data)) == state else { return }
        try? evidence.writeSchemaPromotionEvidence(SchemaPromotionEvidence(
            fromSchemaVersion: AppState.promotableSchemaVersion,
            toSchemaVersion: AppState.currentSchemaVersion,
            backupSHA256: backup.sha256,
            backupByteCount: backup.data.count,
            promotedAt: LegacySnapshotBuilder.instantString(environment.now()),
            operationID: "schema-promotion-\(UUID().uuidString)"
        ))
    }

    private func commitFailure(_ error: Error) -> LaunchOutcome {
        let storeError: StoreError?
        switch error {
        case let commit as StoreCommitError: storeError = commit.underlying
        case let plain as StoreError: storeError = plain
        default: storeError = nil
        }
        // The rename boundary decides first: anything after it (an interruption
        // at `afterReplace` included) is reported as an unconfirmed commit, not
        // as a pre-commit interruption. The next launch inspects the file as usual.
        if case StoreCommitError.indeterminate(let inner) = error {
            return .recovery(.init(kind: .verificationFailed, detail: String(describing: inner), backupAvailable: backupAvailable, canRetry: true))
        }
        if case .interrupted(let stage)? = storeError {
            return .recovery(.init(kind: .interrupted, detail: stage.rawValue, backupAvailable: backupAvailable, canRetry: true))
        }
        return .recovery(.init(kind: .commitFailed, detail: String(describing: error), backupAvailable: backupAvailable, canRetry: true))
    }

    private func interrupted(_ point: InterruptionPoint) -> LaunchOutcome {
        .recovery(.init(kind: .interrupted, detail: point.rawValue, backupAvailable: backupAvailable, canRetry: true))
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
    public var schema2BackupURL: URL { directory.appendingPathComponent("schema2-app-state.json") }
    public var schemaPromotionURL: URL { directory.appendingPathComponent("schema-promotion.json") }

    public init(directory: URL, fileManager: FileManager = .default, attributes: [FileAttributeKey: Any]? = nil) {
        self.directory = directory
        self.fileManager = fileManager
        self.attributes = attributes
    }

    public func inspectBackup() -> EvidenceInspection<BackupRecord> {
        inspect(BackupRecord.self, at: backupURL, decoder: decoder(), supportedVersion: BackupRecord.currentFormatVersion)
    }

    public func writeBackup(_ record: BackupRecord) throws {
        try writeAtomically(try encoder().encode(record), to: backupURL)
    }

    public func inspectCompletion() -> EvidenceInspection<CompletionEvidence> {
        inspect(CompletionEvidence.self, at: completionURL, decoder: JSONDecoder(), supportedVersion: CompletionEvidence.currentFormatVersion)
    }

    /// Existence, readability, declared formats (envelope and, for a backup,
    /// the capture inside it) and decodability are checked in that order so
    /// each failure is reported as what it is: a newer format is `unsupported`
    /// even when its body would not decode with this build.
    private func inspect<T: Decodable>(_ type: T.Type, at url: URL, decoder: JSONDecoder, supportedVersion: Int) -> EvidenceInspection<T> {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { return .unreadable(String(describing: error)) }
        let versions: EvidenceVersionOnly
        do { versions = try JSONDecoder().decode(EvidenceVersionOnly.self, from: data) }
        catch { return .corrupt(String(describing: error)) }
        let version = versions.evidenceFormatVersion ?? 1
        guard version <= supportedVersion else { return .unsupported(version) }
        if let captureVersion = versions.capture?.captureFormatVersion, captureVersion > LegacyCapture.captureFormatVersion {
            return .unsupported(captureVersion)
        }
        do { return .valid(try decoder.decode(T.self, from: data)) }
        catch { return .corrupt(String(describing: error)) }
    }

    public func writeCompletionEvidence(_ evidence: CompletionEvidence) throws {
        try writeAtomically(try encoder().encode(evidence), to: completionURL)
    }

    public func preserveSchema1File(at url: URL) throws {
        try ensureDirectory()
        if fileManager.fileExists(atPath: schema1BackupURL.path) { return }
        try fileManager.copyItem(at: url, to: schema1BackupURL)
    }

    public func inspectSchema2Backup() -> EvidenceInspection<SchemaBackup> {
        guard fileManager.fileExists(atPath: schema2BackupURL.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: schema2BackupURL) }
        catch { return .unreadable(String(describing: error)) }
        switch FileAppStateStore.inspect(data: data) {
        case .legacySchema2: return .valid(SchemaBackup(data: data))
        case .corrupt(let reason): return .corrupt(reason)
        case .ready, .legacySchema1, .unsupportedSchema, .missing, .unreadable:
            return .corrupt("schema 2 backup is not a schema 2 document")
        }
    }

    public func writeSchema2Backup(_ data: Data) throws {
        try ensureDirectory()
        if fileManager.fileExists(atPath: schema2BackupURL.path) { return }
        try writeAtomically(data, to: schema2BackupURL)
    }

    public func inspectSchemaPromotion() -> EvidenceInspection<SchemaPromotionEvidence> {
        inspect(SchemaPromotionEvidence.self, at: schemaPromotionURL, decoder: JSONDecoder(),
                supportedVersion: SchemaPromotionEvidence.currentFormatVersion)
    }

    public func writeSchemaPromotionEvidence(_ evidence: SchemaPromotionEvidence) throws {
        try writeAtomically(try encoder().encode(evidence), to: schemaPromotionURL)
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

private struct EvidenceVersionOnly: Decodable {
    struct CaptureVersionOnly: Decodable { let captureFormatVersion: Int? }
    let evidenceFormatVersion: Int?
    let capture: CaptureVersionOnly?
}
