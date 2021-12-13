//
//  SettingLanguageTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/12/06.
//

import UIKit

class SettingLanguageTableViewCell: UITableViewCell {

    static let identifier = "SettingLanguageTableViewCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
