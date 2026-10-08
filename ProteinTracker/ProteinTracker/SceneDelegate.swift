//
//  SceneDelegate.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import MigrationCore

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var launchGate: RenewalLaunchGate?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // No storyboard is named in Info.plist or the target settings, so
        // nothing (in particular no `try! Realm()` in a storyboard-created
        // view controller) runs before this method decides the route.
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        let paths = RenewalPaths.standard()
        #if DEBUG
        LegacyFixtureSeeder.seedIfRequested(arguments: ProcessInfo.processInfo.arguments, paths: paths)
        #endif

        let gate = RenewalLaunchGate(paths: paths)
        launchGate = gate
        switch gate.route() {
        case .legacy:
            setRootViewController()
        case .renewal:
            startRenewal()
        case .renewalUnsupportedOS:
            window.rootViewController = RecoveryViewController(presentation: .unsupportedOS, retry: nil)
        }
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
    }

}

// MARK: - Renewal flow (explicit opt-in, see RenewalLaunchPolicy)
extension SceneDelegate {
    private func startRenewal() {
        guard let gate = launchGate, let window else { return }
        window.rootViewController = LaunchLoadingViewController()
        gate.run { [weak self] outcome in
            guard let self, let window = self.window else { return }
            switch outcome {
            case .ready(let state):
                if let root = RenewalRootFactory.makeRecordHome(store: gate.screenStore, state: state, now: gate.screenClock,
                                                                makeSearchProvider: gate.searchProviderFactory) {
                    window.rootViewController = root
                } else {
                    window.rootViewController = RecoveryViewController(presentation: .unsupportedOS, retry: nil)
                }
            case .recovery(let recovery):
                window.rootViewController = RecoveryViewController(presentation: .recovery(recovery)) { [weak self] in
                    self?.startRenewal()
                }
            }
        }
    }
}

// MARK: - Legacy flow (unchanged behaviour, now created explicitly)
extension SceneDelegate {
    private func setRootViewController() {
        if Storage.isSetDefaut() {
            setRootView(name: "Show", identifier: "ShowViewController")
        } else {
            setRootView(name: "Init", identifier: "InitViewController")
        }
    }

    private func setRootView(name: String, identifier: String) {
        guard let window else { return }
        let storyBoard = UIStoryboard(name: name, bundle: nil)
        let viewController = storyBoard.instantiateViewController(withIdentifier: identifier)
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
    }
}
