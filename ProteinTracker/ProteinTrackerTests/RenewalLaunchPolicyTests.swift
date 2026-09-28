import XCTest
import MigrationCore

final class RenewalLaunchPolicyTests: XCTestCase {
    func testLegacyPathIsDefaultWithoutFlagOrEvidence() {
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: [], environment: [:], newStoreEvidenceExists: false, isOSSupported: true), .legacy)
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: ["-HelloProteinRenewalFlow", "NO"], environment: [:], newStoreEvidenceExists: false, isOSSupported: true), .legacy)
    }

    func testFlagEnablesRenewalOnlyOnSupportedOS() {
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: ["-HelloProteinRenewalFlow", "YES"], environment: [:], newStoreEvidenceExists: false, isOSSupported: true), .renewal)
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: [], environment: ["HELLOPROTEIN_RENEWAL_FLOW": "1"], newStoreEvidenceExists: false, isOSSupported: true), .renewal)
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: ["-HelloProteinRenewalFlow", "YES"], environment: [:], newStoreEvidenceExists: false, isOSSupported: false), .legacy,
                       "migration must not start on an OS that cannot show the new screen")
    }

    func testNewStoreEvidenceBlocksLegacyPathRegardlessOfFlag() {
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: [], environment: [:], newStoreEvidenceExists: true, isOSSupported: true), .renewal)
        XCTAssertEqual(RenewalLaunchPolicy.route(arguments: [], environment: [:], newStoreEvidenceExists: true, isOSSupported: false), .renewalUnsupportedOS)
    }

    func testDebugArgumentsAreParsedStrictly() {
        XCTAssertEqual(RenewalLaunchPolicy.interruptionPoint(arguments: ["-HelloProteinInterruptAt", "beforeReplace"]), .beforeReplace)
        XCTAssertNil(RenewalLaunchPolicy.interruptionPoint(arguments: ["-HelloProteinInterruptAt", "somewhere"]))
        XCTAssertNil(RenewalLaunchPolicy.interruptionPoint(arguments: ["-HelloProteinInterruptAt"]))
        XCTAssertTrue(RenewalLaunchPolicy.isSeedRequested(arguments: ["-HelloProteinSeedLegacyFixture", "YES"]))
        XCTAssertFalse(RenewalLaunchPolicy.isSeedRequested(arguments: []))
    }

    func testPathsPointToPersistentAppSupportAndDetectEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paths-\(UUID().uuidString)")
        let paths = RenewalPaths(rootDirectory: root)
        XCTAssertFalse(paths.newStoreEvidenceExists())
        try FileManager.default.createDirectory(at: paths.legacyBackupDirectory, withIntermediateDirectories: true)
        XCTAssertFalse(paths.newStoreEvidenceExists(), "a capture/backup directory alone must not block the legacy path")
        try Data("{}".utf8).write(to: paths.completionMarkerURL)
        XCTAssertTrue(paths.newStoreEvidenceExists(), "a completion marker blocks the legacy path")
        try FileManager.default.removeItem(at: paths.completionMarkerURL)
        try Data("{}".utf8).write(to: paths.storeFileURL)
        XCTAssertTrue(paths.newStoreEvidenceExists(), "a store file blocks the legacy path")
        try FileManager.default.removeItem(at: root)
        XCTAssertTrue(RenewalPaths.standard().rootDirectory.path.contains("Application Support"))
    }
}
