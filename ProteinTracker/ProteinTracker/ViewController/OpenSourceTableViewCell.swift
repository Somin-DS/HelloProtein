//
//  OpenSourceTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/12/08.
//

import UIKit

class OpenSourceTableViewCell: UITableViewCell {

    static let identifier = "OpenSourceTableViewCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        self.titleLabel.font = UIFont().bodyFont
    }

    func setText(text: String) {
        self.titleLabel.text = text
    }

}
