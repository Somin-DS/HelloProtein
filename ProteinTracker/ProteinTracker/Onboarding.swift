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
}
