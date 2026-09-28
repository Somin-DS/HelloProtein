import Foundation

/// App-private, persistent locations for the schema 2 store and migration
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

    /// Evidence that a new store was actually committed (the store file itself
    /// or the completion marker). Used to keep the old UIKit path from writing
    /// to the legacy store after migration. A capture/backup directory alone is
    /// not evidence: a migration that failed before commit must not lock the
    /// user out of the still-working legacy app.
    func newStoreEvidenceExists(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: storeFileURL.path)
            || fileManager.fileExists(atPath: completionMarkerURL.path)
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
