//
//  ResultSearchTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/25.
//

import UIKit

class ResultSearchTableViewCell: UITableViewCell {

    @IBOutlet weak var proteinLabel: UILabel!
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
