import Foundation
import MigrationCore
import RealmSwift

enum LegacyGatewayError: Error {
    case backupCopyFailed(String)
    case openFailed(String)
}

/// Reads the old app's data without ever opening the original Realm file.
///
/// - `probe` only checks file existence and defaults keys; it creates nothing.
/// - `capture` copies the closed original into the evidence directory (first
///   copy is kept as the pristine physical backup), then opens a fresh copy
///   read-only. If the copy cannot be opened read-only (file format upgrade),
///   the copy — never the original — is opened writable.
final class RealmLegacySourceGateway: LegacySourceGateway {
    let realmFileURL: URL
    let defaults: UserDefaults
    let backupDirectory: URL
    private let fileManager: FileManager
    private let attributes: [FileAttributeKey: Any]

    init(
        realmFileURL: URL,
        defaults: UserDefaults,
        backupDirectory: URL,
        fileManager: FileManager = .default,
        attributes: [FileAttributeKey: Any] = [:]
    ) {
        self.realmFileURL = realmFileURL
        self.defaults = defaults
        self.backupDirectory = backupDirectory
        self.fileManager = fileManager
        self.attributes = attributes
    }

    static func standard(paths: RenewalPaths) -> RealmLegacySourceGateway {
        RealmLegacySourceGateway(
            realmFileURL: Realm.Configuration.defaultConfiguration.fileURL
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/default.realm"),
            defaults: .standard,
            backupDirectory: paths.legacyBackupDirectory,
            attributes: RenewalPaths.fileProtectionAttributes
        )
    }

    var pristineCopyURL: URL { backupDirectory.appendingPathComponent("default.realm") }

    func probe() throws -> LegacyProbe {
        LegacyProbe(
            realmFilePresent: fileManager.fileExists(atPath: realmFileURL.path),
            presentDefaultsKeys: LegacyRealmSnapshotReader.presentDefaultsKeys(defaults)
        )
    }

    func capture() throws -> LegacyCapture {
        let present = fileManager.fileExists(atPath: realmFileURL.path)
        var rows = LegacyRealmSnapshotReader.Rows()
        if present {
            try ensureBackupDirectory()
            if !fileManager.fileExists(atPath: pristineCopyURL.path) {
                try copyOriginal(to: pristineCopyURL)
            }
            let readCopy = backupDirectory.appendingPathComponent("read-copy-\(UUID().uuidString).realm")
            try copyOriginal(to: readCopy)
            defer { removeRealmFiles(at: readCopy) }
            rows = try readRows(from: readCopy)
        }
        return LegacyRealmSnapshotReader.capture(rows: rows, defaults: defaults, realmFilePresent: present)
    }

    private func ensureBackupDirectory() throws {
        if !fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true,
                                            attributes: attributes.isEmpty ? nil : attributes)
        }
    }

    private func copyOriginal(to destination: URL) throws {
        do {
            try fileManager.copyItem(at: realmFileURL, to: destination)
            if !attributes.isEmpty { try? fileManager.setAttributes(attributes, ofItemAtPath: destination.path) }
        } catch {
            throw LegacyGatewayError.backupCopyFailed(String(describing: error))
        }
    }

    private func readRows(from copy: URL) throws -> LegacyRealmSnapshotReader.Rows {
        var configuration = Realm.Configuration(
            fileURL: copy,
            readOnly: true,
            schemaVersion: 0,
            objectTypes: LegacyRealmSnapshotReader.objectTypes
        )
        do {
            return try autoreleasepool {
                let realm = try Realm(configuration: configuration)
                defer { realm.invalidate() }
                return LegacyRealmSnapshotReader.rows(from: realm)
            }
        } catch {
            // Only the throwaway copy is opened writable, so a file-format
            // upgrade or schema initialization cannot touch the original.
            configuration.readOnly = false
            do {
                return try autoreleasepool {
                    let realm = try Realm(configuration: configuration)
                    defer { realm.invalidate() }
                    return LegacyRealmSnapshotReader.rows(from: realm)
                }
            } catch {
                throw LegacyGatewayError.openFailed(String(describing: error))
            }
        }
    }

    private func removeRealmFiles(at url: URL) {
        for suffix in ["", ".lock", ".note", ".management"] {
            let path = url.path + suffix
            if fileManager.fileExists(atPath: path) { try? fileManager.removeItem(atPath: path) }
        }
    }
}
