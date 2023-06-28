//
//  DailyTargetViewModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/13.
//

import Foundation

final class DailyTargetViewModel: BaseViewModel {
    
    private var dailyTarget = DailyTargetModel()
    
    var weightTitle: String {
        return LocalizeStrings.DT_weightTitle.localized
    }
    
    var weightSegmentTitle: [String] {
        return ["kg","lb"]
    }
    
    var activeTitle: String {
        return LocalizeStrings.DT_activityLevelTitle.localized
    }
    
    var optionalTitle: String {
        return LocalizeStrings.DT_optionalTitle.localized
    }
    
    var targetProteinTitle: String {
        return LocalizeStrings.DT_targetProteinTitle.localized
    }
    
    var targetDescTitle: String {
        return LocalizeStrings.DT_targetProteinDesc.localized
    }
    
    
}
