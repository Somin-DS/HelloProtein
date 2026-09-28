import Foundation
import HelloProteinCore
import MigrationCore

/// Owns the store and runs the migration coordinator off the main thread.
final class RenewalLaunchGate {
    let paths: RenewalPaths
    let store: FileAppStateStore
    private let arguments: [String]
    private let environment: [String: String]
    private let workQueue = DispatchQueue(label: "com.devsom.ProteinTracker.launch-gate", qos: .userInitiated)

    init(paths: RenewalPaths = .standard(),
         arguments: [String] = ProcessInfo.processInfo.arguments,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.paths = paths
        self.arguments = arguments
        self.environment = environment
        let interrupt = Self.interruptHandler(arguments: arguments)
        self.store = FileAppStateStore(
            fileURL: paths.storeFileURL,
            writer: DefaultStoreFileWriter(attributes: RenewalPaths.fileProtectionAttributes),
            directoryAttributes: RenewalPaths.fileProtectionAttributes,
            hooks: StoreCommitHooks { stage in
                switch stage {
                case .temporaryFile: try interrupt(.afterTemporaryWrite)
                case .beforeReplace: try interrupt(.beforeReplace)
                case .afterReplace: try interrupt(.afterReplace)
                default: break
                }
            }
        )
    }

    static var isOSSupported: Bool {
        if #available(iOS 15.0, *) { return true }
        return false
    }

    func route() -> RenewalLaunchRoute {
        RenewalLaunchPolicy.route(
            arguments: arguments,
            environment: environment,
            newStoreEvidenceExists: paths.newStoreEvidenceExists(),
            isOSSupported: Self.isOSSupported
        )
    }

    func run(now: @escaping () -> Date = Date.init, completion: @escaping (LaunchOutcome) -> Void) {
        let interrupt = Self.interruptHandler(arguments: arguments)
        let store = self.store
        let paths = self.paths
        workQueue.async {
            guard let today = CalendarDay.today(now: now(), timeZone: .autoupdatingCurrent) else {
                DispatchQueue.main.async {
                    completion(.recovery(.init(kind: .verificationFailed, detail: "today unavailable",
                                               backupAvailable: false, canRetry: true)))
                }
                return
            }
            let coordinator = MigrationCoordinator(
                store: store,
                legacy: RealmLegacySourceGateway.standard(paths: paths),
                evidence: FileMigrationEvidenceStore(directory: paths.evidenceDirectory,
                                                     attributes: RenewalPaths.fileProtectionAttributes),
                environment: MigrationEnvironment(today: today, now: now, interrupt: interrupt)
            )
            let outcome = coordinator.launch()
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// DEBUG only: `-HelloProteinInterruptAt <point>` kills the process at that
    /// point so the next launch can be checked on the simulator.
    private static func interruptHandler(arguments: [String]) -> (InterruptionPoint) throws -> Void {
        #if DEBUG
        guard let target = RenewalLaunchPolicy.interruptionPoint(arguments: arguments) else { return { _ in } }
        return { point in
            if point == target {
                NSLog("HelloProtein: simulated crash at %@", point.rawValue)
                kill(getpid(), SIGKILL)
            }
        }
        #else
        return { _ in }
        #endif
    }
}
