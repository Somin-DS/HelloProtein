//
//  Onboarding.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/26.
//

import Foundation
import RealmSwift

public class Storage {
    
    static func isSetDefaut() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "targetProtein") == nil {
            return false
        } else {
            return true
        }
    }
    
    static func saveTargetProtein(_ protein: String?){
        
        guard let protein = protein else {return ;}
        UserDefaults.standard.set(protein, forKey: "targetProtein")
    }
    
    static func addTotalProtein(_ protein: Int) {
        
        if UserDefaults.standard.object(forKey: "totalIntake") == nil {
            UserDefaults.standard.set(protein, forKey: "totalIntake")
        } else {
            let totalProtein = UserDefaults.standard.integer(forKey: "totalIntake")
            
            UserDefaults.standard.set(totalProtein + protein, forKey: "totalIntake")
        }
    }
    static func subtractTotalProtein(_ protein: Int) {
        if UserDefaults.standard.object(forKey: "totalIntake") == nil {
            UserDefaults.standard.set(0, forKey: "totalIntake")
        } else {
            let totalProtein = UserDefaults.standard.integer(forKey: "totalIntake")
            
            UserDefaults.standard.set(totalProtein - protein, forKey: "totalIntake")
        }
    }
    
    static func saveDailyTotal (_ date: String, _ total: Int) {
        
        let localRealm = try! Realm()
        let statProtein = StatProtein(date: date, totalIntake: total)
        
        try! localRealm.write {
            localRealm.add(statProtein)
        }
        
        
    }
    static func saveDate (_ date: Date) {
        
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-EEE"
        let date = dateFormatter.string(from: date)
        
        UserDefaults.standard.set(date, forKey: "date")
    }
    
    static func resetData() {
        
        let localRealm = try! Realm()
        
        let dailyRealm = localRealm.objects(DailyProtein.self)
    
        
        try! localRealm.write {
            localRealm.delete(dailyRealm)
        }
        
        UserDefaults.standard.set(0, forKey: "totalIntake")
    }
    
}
