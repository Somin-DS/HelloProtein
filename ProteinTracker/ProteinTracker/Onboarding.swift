//
//  Onboarding.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/26.
//

import Foundation

public class Storage {
    static func isFirstTime() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "isFisrt") == nil {
            defaults.set("No", forKey: "isFirst")
            print("first")
            return true
        } else {
            print("not first time")
            return false
        }
    }
}
