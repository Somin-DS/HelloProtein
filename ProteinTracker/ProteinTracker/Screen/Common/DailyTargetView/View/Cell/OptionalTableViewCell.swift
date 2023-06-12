//
//  OptionalTableViewCell.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/12.
//

import UIKit

class OptionalTableViewCell: UITableViewCell {
    static let identifier = "OptionalTableViewCell"
    @IBOutlet weak var cellLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
