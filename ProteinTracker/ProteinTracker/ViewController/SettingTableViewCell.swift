//
//  SettingTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class SettingTableViewCell: UITableViewCell {

    static let identifier = "SettingTableViewCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setCommonLayout(cornerRadius: 10, borderWidth: 2)
        titleLabel.setCommonLable(font: UIFont().bodyFont)
        detailLabel.setCommonLable(font: UIFont().bodyFont)
    }

    func setText(title: String, detail: String) {
        self.titleLabel.text = title
        self.detailLabel.text = detail
    }
}
