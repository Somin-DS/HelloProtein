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
        self.titleLabel.font = UIFont().bodyFont
        self.titleLabel.textColor = .black
    }
    
    func setText(text: String) {
        self.titleLabel.text = text
    }

}
