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
    #if DEBUG
    /// `-HelloProteinFailAfterReplaceOnce YES`: the first user save after launch
    /// fails right after the rename, which is exactly the "replaced but
    /// unconfirmed" outcome. Armed only once the launch has finished so the
    /// migration commit itself is never affected. Changes no file permissions.
    static let failAfterReplaceArgument = "-HelloProteinFailAfterReplaceOnce"
    private let finalReadFailure = FinalReadFailureInjector()
    /// `-HelloProteinSaveOutcomeOnce notApplied|readFailure`: the first user
    /// save is reported as unconfirmed, and the next re-read of the store
    /// finds it either not applied or unreadable. A test double around the
    /// store for the screen only; the migration commit uses the real store.
    static let saveOutcomeArgument = "-HelloProteinSaveOutcomeOnce"
    /// `-HelloProteinSaveDelaySeconds <n>`: every user write sleeps on the
    /// work queue first, so the busy state can be seen and driven in UI runs.
    static let saveDelayArgument = "-HelloProteinSaveDelaySeconds"
    /// `-HelloProteinAdvanceDayAfterSeconds <n>`: the record screen's clock
    /// jumps one day ahead `n` seconds after launch, which is how a midnight
    /// crossing inside an open sheet is reproduced deterministically.
    static let advanceDayArgument = "-HelloProteinAdvanceDayAfterSeconds"
    /// `-HelloProteinSearchFailOnce network|localData|timeout|service`: the
    /// first food lookup after launch fails that way; later ones are real.
    static let searchFailArgument = "-HelloProteinSearchFailOnce"
    private let saveOutcomeStore: SaveOutcomeInjectingStore?
    private let launchedAt = Date()
    #endif

    /// The clock handed to the record screen. Real time in Release.
    var screenClock: () -> Date {
        #if DEBUG
        if let text = RenewalLaunchPolicy.value(of: Self.advanceDayArgument, in: arguments), let seconds = TimeInterval(text) {
            let launchedAt = self.launchedAt
            return { Date().addingTimeInterval(Date().timeIntervalSince(launchedAt) >= seconds ? 86_400 : 0) }
        }
        #endif
        return Date.init
    }

    /// Food lookup per language for the record screen. Real providers in
    /// Release; DEBUG may wrap the first request in a simulated failure.
    var searchProviderFactory: (SearchLanguage) -> FoodSearchProvider {
        #if DEBUG
        if let failure = RenewalLaunchPolicy.value(of: Self.searchFailArgument, in: arguments)
            .flatMap(FailingOnceSearchProvider.Failure.init(rawValue:)) {
            let wrapper = FailingOnceSearchProvider(inner: SearchProviderFactory.make(for: .english), failure: failure)
            return { language in language == .english ? wrapper : SearchProviderFactory.make(for: language) }
        }
        #endif
        return { SearchProviderFactory.make(for: $0) }
    }

    /// The store handed to the record screen. In Release this is the verified
    /// file store itself.
    var screenStore: AppStateStore {
        #if DEBUG
        if let saveOutcomeStore { return saveOutcomeStore }
        #endif
        return store
    }

    init(paths: RenewalPaths = .standard(),
         arguments: [String] = ProcessInfo.processInfo.arguments,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.paths = paths
        self.arguments = arguments
        self.environment = environment
        let interrupt = Self.interruptHandler(arguments: arguments)
        #if DEBUG
        let injector = finalReadFailure
        #endif
        self.store = FileAppStateStore(
            fileURL: paths.storeFileURL,
            writer: DefaultStoreFileWriter(attributes: RenewalPaths.fileProtectionAttributes),
            directoryAttributes: RenewalPaths.fileProtectionAttributes,
            hooks: StoreCommitHooks { stage in
                switch stage {
                case .temporaryFile: try interrupt(.afterTemporaryWrite)
                case .beforeReplace: try interrupt(.beforeReplace)
                case .afterReplace:
                    try interrupt(.afterReplace)
                    #if DEBUG
                    try injector.fireIfArmed()
                    #endif
                default: break
                }
            }
        )
        #if DEBUG
        let mode = RenewalLaunchPolicy.value(of: Self.saveOutcomeArgument, in: arguments)
            .flatMap(SaveOutcomeInjectingStore.Mode.init(rawValue:))
        let delay = RenewalLaunchPolicy.value(of: Self.saveDelayArgument, in: arguments).flatMap(TimeInterval.init) ?? 0
        if mode != nil || delay > 0 {
            saveOutcomeStore = SaveOutcomeInjectingStore(inner: store, mode: mode, delaySeconds: delay)
        } else {
            saveOutcomeStore = nil
        }
        #endif
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
            #if DEBUG
            if case .ready = outcome,
               RenewalLaunchPolicy.value(of: Self.failAfterReplaceArgument, in: self.arguments).map(RenewalLaunchPolicy.isTruthy) == true {
                self.finalReadFailure.arm()
            }
            #endif
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

#if DEBUG
/// Throws once at the `.afterReplace` commit stage; the store reports the commit
/// as indeterminate. Thread-safe because commits are serialized per path.
final class FinalReadFailureInjector {
    struct SimulatedFinalReadFailure: Error {}
    private let lock = NSLock()
    private var armed = false

    func arm() {
        lock.lock(); defer { lock.unlock() }
        armed = true
    }

    func fireIfArmed() throws {
        lock.lock(); defer { lock.unlock() }
        guard armed else { return }
        armed = false
        NSLog("HelloProtein: simulated final read failure after replace")
        throw SimulatedFinalReadFailure()
    }
}
#endif

#if DEBUG
/// DEBUG-only store double for the record screen. `notApplied`: the first
/// write throws "indeterminate" without touching the file, so the re-read
/// finds nothing. `readFailure`: the first write lands, is reported as
/// indeterminate, and the next `load()` fails once, so the re-read keeps the
/// pending state until it is tried again. Never used in Release builds.
final class SaveOutcomeInjectingStore: AppStateStore {
    enum Mode: String {
        case notApplied
        case readFailure
    }

    private let inner: AppStateStore
    private let lock = NSLock()
    private var pendingMode: Mode?
    private var failNextLoad = false
    private let delaySeconds: TimeInterval

    init(inner: AppStateStore, mode: Mode?, delaySeconds: TimeInterval = 0) {
        self.inner = inner
        self.pendingMode = mode
        self.delaySeconds = delaySeconds
    }

    var unconfirmedOperationID: String? { inner.unconfirmedOperationID }
    var hasUnconfirmedCommit: Bool { inner.hasUnconfirmedCommit }

    func load() throws -> AppState {
        lock.lock()
        let fail = failNextLoad
        failNextLoad = false
        lock.unlock()
        if fail {
            NSLog("HelloProtein: simulated reconfirm read failure")
            throw StoreError.unreadable("simulated reconfirm read failure")
        }
        return try inner.load()
    }

    func modify(operationID: String?, _ change: (inout AppState) throws -> Void) throws -> AppState {
        if delaySeconds > 0 { Thread.sleep(forTimeInterval: delaySeconds) }
        lock.lock()
        let mode = pendingMode
        pendingMode = nil
        lock.unlock()
        switch mode {
        case nil:
            return try inner.modify(operationID: operationID, change)
        case .notApplied:
            NSLog("HelloProtein: simulated indeterminate commit without a write")
            throw StoreCommitError.indeterminate(.verificationMismatch(.finalFile))
        case .readFailure:
            _ = try inner.modify(operationID: operationID, change)
            lock.lock()
            failNextLoad = true
            lock.unlock()
            NSLog("HelloProtein: simulated indeterminate commit after a real write")
            throw StoreCommitError.indeterminate(.verificationMismatch(.finalFile))
        }
    }
}
#endif
