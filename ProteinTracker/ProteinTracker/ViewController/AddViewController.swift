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
    var searchProteinName = ""
    var searchProteinIntake = ""
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
        intakeTextField.delegate = self
        
        title = "Add"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: LocalizeStrings.close_button.localized, style: .plain, target: self, action: #selector(closeButtonClicked))
        navigationItem.rightBarButtonItem?.tintColor = .black
        navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSAttributedString.Key.font: UIFont().bodyFont], for: .normal)

        dailyProteinRealm = localRealm.objects(DailyProtein.self)
        favoriteProteinRealm = localRealm.objects(Favorites.self)
        
        favoriteTableView.estimatedRowHeight = 100
        favoriteTableView.rowHeight = UITableView.automaticDimension
        proteinNameLabel.text = LocalizeStrings.add_namelabel.localized
        proteinNameLabel.font = UIFont().bodyFont
        intakeLabel.text = LocalizeStrings.add_intakelabel.localized
        intakeLabel.font = UIFont().bodyFont
        favoriteLabel.text = LocalizeStrings.add_favoritelabel.localized
        favoriteLabel.font = UIFont().bodyFont
        proteinNameTextField.font = UIFont().bodyFont
        intakeTextField.font = UIFont().bodyFont
        
        customerAddButton.setTitle(LocalizeStrings.add_button.localized, for: .normal)
        customerAddButton.titleLabel?.font = UIFont().bodyFont
        
        favoriteTitleLabel.text = LocalizeStrings.add_favoritelabel.localized
        favoriteTitleLabel.font = UIFont().subFont
        favoriteAddButton.setTitle(LocalizeStrings.add_button.localized, for: .normal)
 
        favoriteAddButton.titleLabel?.font = UIFont().bodyFont
        
//        proteinNameLabel.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
//        proteinNameLabel.layer.borderWidth = 4
        proteinNameLabel.layer.masksToBounds = true
        proteinNameLabel.layer.cornerRadius = 20
        proteinNameTextField.layer.masksToBounds = true
        proteinNameTextField.layer.cornerRadius = 20
        
        intakeTextField.layer.masksToBounds = true
        intakeTextField.layer.cornerRadius = 20
        
//        intakeLabel.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
//        intakeLabel.layer.borderWidth = 4
        intakeLabel.layer.masksToBounds = true
        intakeLabel.layer.cornerRadius = 20
        
//        favoriteLabel.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
//        favoriteLabel.layer.borderWidth = 4
        favoriteLabel.layer.masksToBounds = true
        favoriteLabel.layer.cornerRadius = 20
        
        searchButton.layer.masksToBounds = true
        searchButton.layer.cornerRadius = 15
        searchButton.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        searchButton.layer.borderWidth = 2
        favoriteAddButton.layer.masksToBounds = true
        favoriteAddButton.layer.cornerRadius = 10
        favoriteAddButton.tintColor = .black
        favoriteAddButton.backgroundColor =
        UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 0.8)
        customerAddButton.layer.masksToBounds = true
        customerAddButton.layer.cornerRadius = 10
        customerAddButton.tintColor = .black

        customerAddButton.backgroundColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 0.8)
        intakeTextField.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        intakeTextField.layer.borderWidth = 2
        
        proteinNameTextField.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        proteinNameTextField.layer.borderWidth = 2
    }

    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(updateNameTextField(_:)), name: .proteinName, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateIntakeTextField(_:)), name: .proteinIntake, object: nil)
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
            let windows = UIApplication.shared.windows
            windows.last?.makeToast(LocalizeStrings.empty_name.localized)
//            self.view.makeToast(LocalizeStrings.empty_name.localized)
            return;
        }
        if isValidNumber(intakeTextField.text) != 0{
            if isValidNumber(intakeTextField.text) == 1{
                let windows = UIApplication.shared.windows
                windows.last?.makeToast(LocalizeStrings.empty_protein.localized)
//                self.view.makeToast(LocalizeStrings.empty_protein.localized)
            }else {
                let windows = UIApplication.shared.windows
                windows.last?.makeToast(LocalizeStrings.error_number.localized)
//                self.view.makeToast(LocalizeStrings.error_number.localized)
            }
            return;
        }
        
        if favoriteFlag == 1 {
            let favoriteProtein = Favorites(proteinName: proteinNameTextField.text!, proteinIntake: Int(intakeTextField.text!)!)
            if favoriteProteinRealm.filter("proteinName == '\(favoriteProtein.proteinName)'").count > 0 {
                let windows = UIApplication.shared.windows
                windows.last?.makeToast(LocalizeStrings.error_duplicate.localized)
//                self.view.makeToast(LocalizeStrings.error_duplicate.localized)
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
            favoriteFlag = 0
            favoriteTableView.reloadData()
        }
       
    }
    
    @IBAction func favoriteAddButtonClicked(_ sender: UIButton) {
        
        if favoriteName == nil || favoriteIntake == nil {
            let windows = UIApplication.shared.windows
            windows.last?.makeToast(LocalizeStrings.empty_favorite.localized)
//            self.view.makeToast(LocalizeStrings.empty_favorite.localized)
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
            favoriteName = nil
            favoriteIntake = nil
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
        cell.nameLabel.textAlignment = .center
        cell.nameLabel.numberOfLines = 0
        cell.nameLabel.lineBreakMode = .byWordWrapping
        cell.nameLabel.font = UIFont().bodyFont
        cell.intakeLabel.textAlignment = .center
        cell.intakeLabel.numberOfLines = 0
        cell.intakeLabel.lineBreakMode = .byWordWrapping
        cell.intakeLabel.font = UIFont().bodyFont
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

extension AddViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text else { return true }
        let newLength = text.count + string.count - range.length
        return newLength <= 5
    }
}

extension AddViewController {
    @objc func updateNameTextField(_ notification: NSNotification) {
        if let txt = notification.userInfo?["name"] as? String {
            self.proteinNameTextField.text = txt
        }
    }
    
    @objc func updateIntakeTextField(_ notification: NSNotification) {
        if let txt = notification.userInfo?["intake"] as? String {
            self.intakeTextField.text = "\(Int(Double(txt) ?? 0.0))"
        }
    }
}
