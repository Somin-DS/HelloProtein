//
//  ShowTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class ShowTableViewCell: UITableViewCell {

    static let identifier = "ShowTableViewCell"
    
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.setCommonLayout(cornerRadius: 5, borderWidth: 1)
        intakeLabel.setCommonLable(font: UIFont().bodyFont)
        nameLabel.setCommonLable(font: UIFont().bodyFont)
        
    }
    func setText(name: String, intake: String) {
        self.nameLabel.text = name
        self.intakeLabel.text = intake
    }

}
