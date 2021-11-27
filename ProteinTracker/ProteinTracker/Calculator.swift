//
//  Calculator.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/27.
//

import Foundation
import SwiftUI

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
