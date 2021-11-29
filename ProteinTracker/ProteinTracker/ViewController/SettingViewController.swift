//
//  SettingViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class SettingViewController: UIViewController {

    let settings: [[String]] = [[LocalizeStrings.setting_intake.localized, "targetProtein"]]
    
    @IBOutlet weak var settingTableView: UITableView!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        settingTableView.delegate = self
        settingTableView.dataSource = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        title = "Setting"
    }
    override func viewWillAppear(_ animated: Bool) {
        settingTableView.reloadData()
    }
    

}

extension SettingViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settings.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = settingTableView.dequeueReusableCell(withIdentifier: SettingTableViewCell.identifier, for: indexPath) as? SettingTableViewCell else { return UITableViewCell()}
        
        let row = settings[indexPath.row]
        cell.titleLabel.text = row[0]
        cell.detailLabel.text = "\(UserDefaults.standard.string(forKey: row[1])!) g"
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "SettingTargetViewController") as! SettingTargetViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
}
