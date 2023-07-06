//
//  DailyTargetCellViewModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/28.
//

import Foundation

enum CellType {
    case activityLevel
    case optiontional
}

struct DailyTargetCellViewModel {
    var text: String
    var isSelect = false
}
