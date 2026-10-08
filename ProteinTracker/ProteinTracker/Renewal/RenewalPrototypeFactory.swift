import UIKit
import SwiftUI
import HelloProteinCore

/// UIKit integration seam for the renewal flow. The screen receives a store
/// that the start gate has already verified; it never creates empty models.
enum RenewalRootFactory {
    static func makeRecordHome(store: AppStateStore, state: AppState, now: @escaping () -> Date = Date.init,
                               makeSearchProvider: ((SearchLanguage) -> FoodSearchProvider)? = nil) -> UIViewController? {
        guard #available(iOS 15.0, *) else { return nil }
        let model = RecordHomeViewModel(store: store, state: state, now: now)
        let home = RecordHomeView(model: model, makeSearchProvider: makeSearchProvider ?? { SearchProviderFactory.make(for: $0) })
        return UIHostingController(rootView: home)
    }
}
