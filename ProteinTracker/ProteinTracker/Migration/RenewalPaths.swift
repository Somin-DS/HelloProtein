import Foundation

/// App-private, persistent locations for the app-state store and migration
/// evidence. Never the caches or temporary directory.
struct RenewalPaths {
    let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    static func standard(fileManager: FileManager = .default) -> RenewalPaths {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return RenewalPaths(rootDirectory: base.appendingPathComponent("HelloProtein", isDirectory: true))
    }

    var storeFileURL: URL { rootDirectory.appendingPathComponent("app-state.json") }
    var evidenceDirectory: URL { rootDirectory.appendingPathComponent("migration", isDirectory: true) }
    var legacyBackupDirectory: URL { evidenceDirectory.appendingPathComponent("legacy-backup", isDirectory: true) }

    var completionMarkerURL: URL { evidenceDirectory.appendingPathComponent("migration-completed.json") }

    var schema2BackupURL: URL { evidenceDirectory.appendingPathComponent("schema2-app-state.json") }
    var schemaPromotionURL: URL { evidenceDirectory.appendingPathComponent("schema-promotion.json") }

    /// A schema promotion backup/marker also proves that the new store existed.
    /// Presence forces the recovery-capable route even if the evidence is corrupt;
    /// MigrationCoordinator validates it. Ordinary legacy capture directories do
    /// not prove a commit and must not block the legacy path by themselves.
    func newStoreEvidenceExists(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: storeFileURL.path)
            || fileManager.fileExists(atPath: completionMarkerURL.path)
            || fileManager.fileExists(atPath: schema2BackupURL.path)
            || fileManager.fileExists(atPath: schemaPromotionURL.path)
    }

    /// Readable after the first unlock so a background relaunch does not see
    /// an "unreadable" store and mistake it for a fresh install.
    static var fileProtectionAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        return [:]
        #endif
    }
}
