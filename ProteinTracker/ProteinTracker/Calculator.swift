//
//  Calculator.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/27.
//

import Foundation
import SwiftUI
//import RealmSwift

func calculateTargetProtein( _ weight: Double, _ weightMeasure: String, _ activityLevel: Activity) -> String {
    
    let protein: Double
    
    if weightMeasure == "kg"
    {
        switch activityLevel {
        case .light:
            protein = weight * 1.2
        case .moderate:
            protein = weight * 1.4
        case .active:
            protein = weight * 1.6
        }
    }else {
        switch activityLevel {
        case .light:
            protein = weight * 0.54
        case .moderate:
            protein = weight * 0.64
        case .active:
            protein = weight * 0.73
        }
    }
    return String(format: "%.1f", protein)
}

func calculatePercentage() -> Double {
    
    let target = UserDefaults.standard.integer(forKey: "targetProtein")
    let current = UserDefaults.standard.integer(forKey: "totalIntake")
    
    if current == 0 {
        return 0
    }
    return (Double(current) / Double(target))
}

func calculateAverageProtein(_ values: [Double]) -> String {
    
    var totalProtein: Double = 0
    var count = 0
    for i in values {
        if i != 0 {
            totalProtein += i
            count += 1
        }
    }
    
    if totalProtein == 0 {
        return "0"
    }
    return  String(format: "%.1f", (totalProtein / Double(count)))
}

//func calculateAverageProtein() -> Int {
//
//    let localRealm = try! Realm()
//
//    let statRealm = localRealm.objects(StatProtein.self)
//
//    var totalProtein = 0
//
//    for i in statRealm {
//        totalProtein += i.totalIntake
//    }
//
//    if totalProtein == 0 {
//        return 0
//    }
//
//    return totalProtein / statRealm.count
//}
