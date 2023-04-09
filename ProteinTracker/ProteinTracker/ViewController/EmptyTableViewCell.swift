//
//  EmptyTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/12/07.
//

import UIKit

class EmptyTableViewCell: UITableViewCell {

    static let identifier = "EmptyTableViewCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func setText(text: String) {
        self.titleLabel.text = text
    }

}
