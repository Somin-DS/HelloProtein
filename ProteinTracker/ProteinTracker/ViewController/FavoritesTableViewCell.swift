//
//  FavoritesTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class FavoritesTableViewCell: UITableViewCell {

    static let identifier = "FavoritesTableViewCell"
    
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
      
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

      
    }

}
