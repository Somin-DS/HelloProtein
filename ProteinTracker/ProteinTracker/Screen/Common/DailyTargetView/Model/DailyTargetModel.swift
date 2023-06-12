//
//  DailyTargetModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/13.
//

import Foundation

enum ActivityLevel {
    case sedentary, light, moderate, veryActive
}

enum targetOption {
    case pregnant, breastfeeding, elderly
}

enum Unit {
    case kg, pound
}
struct DailyTargetModel {
    var weight: Double
    var weightUnit: Unit
    var activityLevel: ActivityLevel
    var optional: targetOption
    var targetProtein: Int
}
