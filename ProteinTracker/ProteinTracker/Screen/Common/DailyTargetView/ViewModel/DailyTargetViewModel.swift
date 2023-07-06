//
//  DailyTargetViewModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/13.
//

import Foundation

final class DailyTargetViewModel: BaseViewModel {
    
    private var dailyTarget = DailyTargetModel()
    
    private var activityCellViewModels = [DailyTargetCellViewModel]() {
        didSet {
            reloadTableView?(.activityLevel)
        }
    }
    
    private var optionalCellViewModels = [DailyTargetCellViewModel]() {
        didSet {
            reloadTableView?(.optiontional)
        }
    }
    
    var reloadTableView: ((CellType) -> Void)?
    
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
    
    var numberOfActivityLevel: Int {
        return activityCellViewModels.count
    }
    
    var numberOfOptional: Int {
        return optionalCellViewModels.count
    }
    
    override init() {
        super.init()
        createCellViewModel(type: .optiontional)
        createCellViewModel(type: .activityLevel)
    }
    
    private func createCellViewModel(type: CellType) {
        if type == .activityLevel {
            activityCellViewModels = ActivityLevel.allCases.map{($0.getString())}.map{DailyTargetCellViewModel(text: $0)}
        } else {
            optionalCellViewModels = TargetOption.allCases.map{($0.getString())}.map{DailyTargetCellViewModel(text: $0)}
        }
    }
    
    func getCellViewModel(type: CellType, at index: IndexPath) -> DailyTargetCellViewModel {
        if type == .activityLevel {
           return activityCellViewModels[index.row]
        } else {
            return optionalCellViewModels[index.row]
        }
    }
    
    func selectCell(type: CellType, at index: IndexPath) {
        if type == .activityLevel {
            activityCellViewModels
            activityCellViewModels[index.row].isSelect = !activityCellViewModels[index.row].isSelect
            
        } else {
            optionalCellViewModels[index.row].isSelect = !optionalCellViewModels[index.row].isSelect
        }
    }
}
