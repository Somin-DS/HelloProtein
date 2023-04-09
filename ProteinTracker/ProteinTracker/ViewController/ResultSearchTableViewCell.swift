//
//  ResultSearchTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/25.
//

import UIKit

class ResultSearchTableViewCell: UITableViewCell {

    static let identifier = "ResultSearchTableViewCell"
    @IBOutlet weak var proteinLabel: UILabel!

    @IBOutlet weak var nameLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.proteinLabel.setCommonLable(font: UIFont.systemFont(ofSize: 17))
        self.nameLabel.setCommonLable(font: UIFont.systemFont(ofSize: 17))
    }

    func setText(name: String, protein: String) {
        self.nameLabel.text = name
        self.proteinLabel.text = protein
    }

}
