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

enum TargetOption {
    case pregnant, breastfeeding, elderly
}

enum Unit: String {
    case kg, lb
}

struct DailyTargetModel {
    var weight: Double?
    var weightUnit: Unit?
    var activityLevel: ActivityLevel?
    var optional: TargetOption?
    var targetProtein: Int = 0
}
