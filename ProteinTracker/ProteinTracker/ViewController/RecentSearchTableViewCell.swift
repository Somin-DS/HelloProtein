//
//  RecentSearchTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/25.
//

import UIKit

class RecentSearchTableViewCell: UITableViewCell {

    static let identifier = "RecentSearchTableViewCell"
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var recentLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        
    }

    func setText(text: String) {
        self.recentLabel.text = text
    }
}
