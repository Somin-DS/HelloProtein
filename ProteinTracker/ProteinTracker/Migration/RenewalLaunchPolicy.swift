import Foundation
import MigrationCore

enum RenewalLaunchRoute: Equatable {
    /// The unchanged storyboard/UIKit path.
    case legacy
    /// Run the start gate (migration if needed) and show the SwiftUI screen.
    case renewal
    /// A new store exists but this OS cannot show the new screen. The old
    /// path must not run either, because it would write to the legacy store.
    case renewalUnsupportedOS
}

/// Pure decision so it can be unit tested without UIKit.
enum RenewalLaunchPolicy {
    static let flagArgument = "-HelloProteinRenewalFlow"
    static let flagEnvironment = "HELLOPROTEIN_RENEWAL_FLOW"
    static let interruptArgument = "-HelloProteinInterruptAt"
    static let seedArgument = "-HelloProteinSeedLegacyFixture"

    static func route(
        arguments: [String],
        environment: [String: String],
        newStoreEvidenceExists: Bool,
        isOSSupported: Bool
    ) -> RenewalLaunchRoute {
        if newStoreEvidenceExists {
            return isOSSupported ? .renewal : .renewalUnsupportedOS
        }
        guard isFlagEnabled(arguments: arguments, environment: environment) else { return .legacy }
        return isOSSupported ? .renewal : .legacy
    }

    static func isFlagEnabled(arguments: [String], environment: [String: String]) -> Bool {
        if let value = value(of: flagArgument, in: arguments), isTruthy(value) { return true }
        if let value = environment[flagEnvironment], isTruthy(value) { return true }
        return false
    }

    static func interruptionPoint(arguments: [String]) -> InterruptionPoint? {
        value(of: interruptArgument, in: arguments).flatMap(InterruptionPoint.init(rawValue:))
    }

    static func isSeedRequested(arguments: [String]) -> Bool {
        value(of: seedArgument, in: arguments).map(isTruthy) ?? false
    }

    static func value(of argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func isTruthy(_ value: String) -> Bool {
        ["1", "YES", "yes", "true", "TRUE"].contains(value)
    }
}
