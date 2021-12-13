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
        self.layer.borderColor = UIColor(red: 200.0/255.0, green: 244.0/255.0, blue: 194.0/255.0, alpha: 1.0).cgColor
        self.layer.cornerRadius = 5
        self.layer.masksToBounds = true
        self.layer.borderWidth = 1
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
