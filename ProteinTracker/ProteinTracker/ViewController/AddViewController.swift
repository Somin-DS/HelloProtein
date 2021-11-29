//
//  AddViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import RealmSwift
import Toast

class AddViewController: UIViewController {

    let localRealm = try! Realm()
    var dailyProteinRealm: Results<DailyProtein>!
    var favoriteProteinRealm: Results<Favorites>!
    var favoriteName: String? = nil
    var favoriteIntake: Int? = nil
    @IBOutlet weak var proteinNameLabel: UILabel!
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var favoriteLabel: UILabel!
    @IBOutlet weak var favoriteSwitch: UISwitch!
    @IBOutlet weak var intakeTextField: UITextField!
    @IBOutlet weak var proteinNameTextField: UITextField!
    @IBOutlet weak var searchButton: UIButton!
    @IBOutlet weak var customerAddButton: UIButton!
    
    @IBOutlet weak var favoriteTitleLabel: UILabel!
    @IBOutlet weak var favoriteAddButton: UIButton!
    @IBOutlet weak var favoriteTableView: UITableView!
    
    var favoriteFlag = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        favoriteTableView.delegate = self
        favoriteTableView.dataSource = self
        
        title = "Add"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: LocalizeStrings.close_button.localized, style: .plain, target: self, action: #selector(closeButtonClicked))
        
        dailyProteinRealm = localRealm.objects(DailyProtein.self)
        favoriteProteinRealm = localRealm.objects(Favorites.self)
        
        proteinNameLabel.text = LocalizeStrings.add_namelabel.localized
        intakeLabel.text = LocalizeStrings.add_intakelabel.localized
        favoriteLabel.text = LocalizeStrings.add_favoritelabel.localized
        customerAddButton.titleLabel?.text = LocalizeStrings.add_button.localized
        
        favoriteTitleLabel.text = LocalizeStrings.add_favoritelabel.localized
        favoriteAddButton.titleLabel?.text = LocalizeStrings.add_button.localized
        
    }
    
    @objc func closeButtonClicked(){
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func addTapGesture(_ sender: UITapGestureRecognizer) {
        
        view.endEditing(true)
    }
    
    @IBAction func searchButtonClicked(_ sender: UIButton) {
        
        let sb = UIStoryboard(name: "Add", bundle: nil)
        
        let vc = sb.instantiateViewController(withIdentifier: "SearchViewController")
        
        let nav = UINavigationController(rootViewController: vc)
        
        self.present(nav, animated: true, completion: nil)
    }
    
    @IBAction func favoriteToggle(_ sender: UISwitch) {
        
        if sender.isOn {
            favoriteFlag = 1
        }else {
            favoriteFlag = 0
        }
    }
    
    @IBAction func customerAddButtonClicked(_ sender: UIButton) {
        
        if isValidString(proteinNameTextField.text) != 0 {
            self.view.makeToast(LocalizeStrings.empty_name.localized)
            return;
        }
        if isValidNumber(intakeTextField.text) != 0{
            if isValidNumber(intakeTextField.text) == 1{
                self.view.makeToast(LocalizeStrings.empty_protein.localized)
            }else {
                self.view.makeToast(LocalizeStrings.error_number.localized)
            }
            return;
        }
        
        if favoriteFlag == 1 {
            let favoriteProtein = Favorites(proteinName: proteinNameTextField.text!, proteinIntake: Int(intakeTextField.text!)!)
            if favoriteProteinRealm.filter("proteinName == '\(favoriteProtein.proteinName)'").count > 0 {
                
                self.view.makeToast(LocalizeStrings.error_duplicate.localized)
                return ;
            }else {
                try! localRealm.write {
                    localRealm.add(favoriteProtein)
                }
            }
        }
        let addProtein = DailyProtein(proteinName: proteinNameTextField.text!, proteinIntake: Int(intakeTextField.text!)!)
        let alert = UIAlertController(title: LocalizeStrings.alert_addTitle.localized, message: LocalizeStrings.alert_addContent.localized, preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: LocalizeStrings.close_button.localized, style: .cancel, handler: nil)
        alert.addAction(cancelAction)
        try! localRealm.write {
            localRealm.add(addProtein)
            Storage.addTotalProtein(addProtein.proteinIntake)
            self.present(alert, animated: false)
            intakeTextField.text = ""
            proteinNameTextField.text = ""
            favoriteSwitch.isOn = false
            favoriteTableView.reloadData()
        }
       
    }
    
    @IBAction func favoriteAddButtonClicked(_ sender: UIButton) {
        
        if favoriteName == nil || favoriteIntake == nil {
            self.view.makeToast(LocalizeStrings.empty_favorite.localized)
        }else {
            
            let dailyProtein = DailyProtein(proteinName: favoriteName!, proteinIntake: favoriteIntake!)
            try! localRealm.write {
                localRealm.add(dailyProtein)
                Storage.addTotalProtein(dailyProtein.proteinIntake)
            }
            
            let alert = UIAlertController(title: LocalizeStrings.alert_addTitle.localized, message: LocalizeStrings.alert_addContent.localized, preferredStyle: .alert)
            
            let cancelAction = UIAlertAction(title: LocalizeStrings.close_button.localized, style: .cancel, handler: nil)
            alert.addAction(cancelAction)
            self.present(alert, animated: false)
            favoriteTableView.reloadData()
        }
    }
    
}

extension AddViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return favoriteProteinRealm.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = favoriteTableView.dequeueReusableCell(withIdentifier: FavoritesTableViewCell.identifier, for: indexPath) as? FavoritesTableViewCell else {
            return UITableViewCell()
        }
        
        let row = favoriteProteinRealm[indexPath.row]
        cell.nameLabel.text = row.proteinName
        cell.intakeLabel.text =
        "\(row.proteinIntake) g"
        
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        favoriteName = favoriteProteinRealm[indexPath.row].proteinName
        favoriteIntake = favoriteProteinRealm[indexPath.row].proteinIntake
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        
        try! localRealm.write {
            localRealm.delete(favoriteProteinRealm[indexPath.row])
            favoriteTableView.reloadData()
        }
    }

}
