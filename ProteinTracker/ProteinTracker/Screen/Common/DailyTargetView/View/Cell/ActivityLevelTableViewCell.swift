//
//  ActivityLevelTableViewCell.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/12.
//

import UIKit

class ActivityLevelTableViewCell: UITableViewCell {
    static let identifier = "ActivityLevelTableViewCell"

    @IBOutlet weak var cellLabel: UILabel!
    
    func configureCell(viewModel: DailyTargetCellViewModel) {
        cellLabel.setTitleText(viewModel.text, color: .black, size: 17)
//        self.accessoryType =  viewModel.isSelect ? .checkmark : .none
    }

}
