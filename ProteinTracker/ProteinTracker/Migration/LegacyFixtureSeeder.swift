#if DEBUG
import Foundation
import RealmSwift

/// Simulator-only synthetic legacy data written through the old models, so
/// the migration can be exercised without real user data. Runs only when
/// `-HelloProteinSeedLegacyFixture YES` is passed and no renewal store exists.
enum LegacyFixtureSeeder {
    static func seedIfRequested(arguments: [String], paths: RenewalPaths) {
        guard RenewalLaunchPolicy.isSeedRequested(arguments: arguments),
              !paths.newStoreEvidenceExists() else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "targetProtein") == nil else { return } // seed once
        do {
            let realm = try Realm()
            // Never interleave fixture rows with genuine data on a device that already has any.
            guard realm.objects(DailyProtein.self).isEmpty, realm.objects(StatProtein.self).isEmpty,
                  realm.objects(Favorites.self).isEmpty, realm.objects(SearchHistory.self).isEmpty else {
                NSLog("HelloProtein: legacy fixture not seeded, existing rows present")
                return
            }
            try realm.write {
                realm.add(DailyProtein(proteinName: "우유", proteinIntake: 10))
                realm.add(DailyProtein(proteinName: "계란 2개", proteinIntake: 35))
                realm.add(StatProtein(date: "2026-09-20-일", originDate: Date(timeIntervalSince1970: 1_789_862_400), totalIntake: 70))
                realm.add(StatProtein(date: "2026-09-21-월", originDate: Date(timeIntervalSince1970: 1_789_948_800), totalIntake: 0))
                realm.add(StatProtein(date: "2026-09-22-화", originDate: Date(timeIntervalSince1970: 1_790_035_200), totalIntake: 15))
                realm.add(Favorites(proteinName: "닭가슴살", proteinIntake: 23))
                realm.add(Favorites(proteinName: "그릭요거트", proteinIntake: 9))
                realm.add(SearchHistory(proteinName: "egg"))
                realm.add(SearchHistory(proteinName: "milk"))
            }
            defaults.set("2026-09-23-화", forKey: "date")
            defaults.set(Date(timeIntervalSince1970: 1_790_121_600), forKey: "Date")
            defaults.set(55, forKey: "totalIntake") // details sum to 45 → +10 g adjustment
            defaults.set("120", forKey: "targetProtein")
            defaults.set("Korean(한글)", forKey: "searchLanguage")
            NSLog("HelloProtein: legacy fixture seeded")
        } catch {
            NSLog("HelloProtein: legacy fixture seeding failed: %@", String(describing: error))
        }
    }
}
#endif
