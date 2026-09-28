import UIKit
import SwiftUI
import HelloProteinCore

/// UIKit integration seam for the renewal flow. The screen receives a store
/// that the start gate has already verified; it never creates empty models.
enum RenewalRootFactory {
    static func makeRecordHome(store: AppStateStore, state: AppState) -> UIViewController? {
        guard #available(iOS 15.0, *) else { return nil }
        let model = RecordHomeViewModel(store: store, state: state)
        return UIHostingController(rootView: RecordHomeView(model: model))
    }
}
