//
//  FavoritesTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class FavoritesTableViewCell: UITableViewCell {

    static let identifier = "FavoritesTableViewCell"
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var intakeLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.nameLabel.setCommonLable(font: UIFont().bodyFont)
        self.intakeLabel.setCommonLable(font: UIFont().bodyFont)
    }
    
    func setText(name: String, intake: String) {
        self.nameLabel.text = name
        self.intakeLabel.text = intake
    }
}
