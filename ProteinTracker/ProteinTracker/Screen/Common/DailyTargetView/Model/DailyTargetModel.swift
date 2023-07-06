//
//  DailyTargetModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/13.
//

import Foundation

enum ActivityLevel: Int, CaseIterable {
    case sedentary, light, moderate, veryActive
    
    func getString() -> String {
        switch self {
        case .sedentary:
            return LocalizeStrings.DT_activityLevelOption1.localized
        case .light:
            return LocalizeStrings.DT_activityLevelOption2.localized
        case .moderate:
            return LocalizeStrings.DT_activityLevelOption3.localized
        case .veryActive:
            return LocalizeStrings.DT_activityLevelOption4.localized
        }
    }
}

enum TargetOption: Int, CaseIterable {
    case pregnant, breastfeeding, elderly
    
    func getString() -> String {
        switch self {
        case .pregnant:
            return LocalizeStrings.DT_optionalOption1.localized
        case .breastfeeding:
            return LocalizeStrings.DT_optionalOption2.localized
        case .elderly:
            return LocalizeStrings.DT_optionalOption3.localized
        }
    }
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

