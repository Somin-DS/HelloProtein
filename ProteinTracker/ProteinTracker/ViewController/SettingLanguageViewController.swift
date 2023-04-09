//
//  SettingLanguageViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/12/06.
//

import UIKit

class SettingLanguageViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    let languageSet: [String] = ["Korean(한글)", "English(영어)"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
        title = "Search Language"
    }
}

extension SettingLanguageViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return languageSet.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SettingLanguageTableViewCell.identifier, for: indexPath) as? SettingLanguageTableViewCell else {return UITableViewCell()}
        cell.setText(text: languageSet[indexPath.row])
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        UserDefaults.standard.set(languageSet[indexPath.row], forKey: "searchLanguage")
    }
    
}
