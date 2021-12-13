//
//  InfoOpenSourceViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/12/08.
//

import UIKit
import SwiftUI

class InfoOpenSourceViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    
    let sectionArray = [LocalizeStrings.setting_opensource.localized, "API"]
    
    let openSource = ["Alamofire", "SwiftyJSON", "Realm", "Charts", "Toast", "TextFieldEffects", "IQKeyboardManagerSwift", "JGProgressHUD"]
    
    let api = ["식품의약품안전처_식품 영양성분 정보", "FoodData Central"]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
    }


}

extension InfoOpenSourceViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: OpenSourceTableViewCell.identifier, for: indexPath) as? OpenSourceTableViewCell else {return UITableViewCell()}
        
        if indexPath.section == 0 {
            cell.titleLabel.text = openSource[indexPath.row]
        }else {
            cell.titleLabel.text = api[indexPath.row]
        }
        
        cell.titleLabel.font = UIFont().bodyFont
        
        return cell
    }
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionArray[section]
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return openSource.count
        }else {
            return api.count
        }
    }
}
