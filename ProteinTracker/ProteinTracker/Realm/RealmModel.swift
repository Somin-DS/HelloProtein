//
//  RealmModel.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/27.
//

import Foundation
import RealmSwift


class DailyProtein: Object {
    @Persisted var proteinName: String
    @Persisted var proteinIntake: Int
    
    @Persisted(primaryKey: true) var _id: ObjectId
    
    convenience init(proteinName: String, proteinIntake: Int) {
        self.init()
        
        self.proteinName = proteinName
        self.proteinIntake = proteinIntake
    }
}

class StatProtein: Object {
    @Persisted var date: String
    @Persisted var totalIntake: Int
    
    @Persisted(primaryKey: true) var _id: ObjectId
    
    convenience init(date: String, totalIntake: Int) {
        self.init()
        
        self.date = date
        self.totalIntake = totalIntake
    }
}

class Favorites: Object {
    @Persisted var proteinName: String
    @Persisted var proteinIntake: Int
    
    @Persisted(primaryKey: true) var _id: ObjectId
    
    convenience init(proteinName: String, proteinIntake: Int) {
        self.init()
        
        self.proteinName = proteinName
        self.proteinIntake = proteinIntake
    }
}
