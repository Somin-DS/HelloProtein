//
//  SettingTableViewCell.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class SettingTableViewCell: UITableViewCell {

    static let identifier = "SettingTableViewCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var detailLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
       
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        
    }

}
