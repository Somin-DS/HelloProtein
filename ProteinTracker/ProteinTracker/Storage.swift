//
//  Onboarding.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/26.
//

import Foundation

public class Storage {
    
    static func isSetDefaut() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "targetProtein") == nil {
            return false
        } else {
            return true
        }
    }
    
    static func saveTargetProtein(_ protein: String){
        UserDefaults.standard.set(protein, forKey: "targetProtein")
    }
    
    static func saveLanguageSetting() {
        let localeID = Locale.preferredLanguages.first
        let deviceLocale = (Locale(identifier: localeID!).languageCode)!
        
        UserDefaults.standard.set(deviceLocale, forKey:"languageSetting")
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
    
}
