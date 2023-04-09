//
//  AddViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import RealmSwift

class AddViewController: UIViewController {

    let localRealm = try! Realm()
    lazy var dailyProteinRealm = localRealm.objects(DailyProtein.self)
    lazy var favoriteProteinRealm = localRealm.objects(Favorites.self)
    var favoriteName: String? = nil
    var favoriteIntake: Int? = nil
    var searchProteinName = ""
    var searchProteinIntake = ""
    var favoriteFlag = 0
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

    override func viewDidLoad() {
        super.viewDidLoad()
        setDelegete()
        setUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(updateNameTextField(_:)), name: .proteinName, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateIntakeTextField(_:)), name: .proteinIntake, object: nil)
    }
    
    func setDelegete() {
        favoriteTableView.delegate = self
        favoriteTableView.dataSource = self
        intakeTextField.delegate = self
    }
    
    func setUI() {
        title = "Add"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: LocalizeStrings.close_button.localized, style: .plain, target: self, action: #selector(closeButtonClicked))
        navigationItem.rightBarButtonItem?.tintColor = .black
        navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSAttributedString.Key.font: UIFont().bodyFont], for: .normal)

        favoriteTableView.estimatedRowHeight = 100
        favoriteTableView.rowHeight = UITableView.automaticDimension
        
        proteinNameLabel.setText(text: LocalizeStrings.add_namelabel.localized, font: UIFont().bodyFont)
        proteinNameLabel.setCornerRadius(cornerRadius: 20)
        intakeLabel.setText(text: LocalizeStrings.add_intakelabel.localized, font: UIFont().bodyFont)
        intakeLabel.setCornerRadius(cornerRadius: 20)
        favoriteLabel.setText(text: LocalizeStrings.add_favoritelabel.localized, font: UIFont().bodyFont)
        favoriteLabel.setCornerRadius(cornerRadius: 20)
        proteinNameTextField.font = UIFont().bodyFont
        proteinNameTextField.setCommonLayout(cornerRadius: 20, borderWidth: 2)
        intakeTextField.font = UIFont().bodyFont
        intakeTextField.setCommonLayout(cornerRadius: 20, borderWidth: 2)
        customerAddButton.setText(text: LocalizeStrings.add_button.localized, font: UIFont().bodyFont, textColor: .black)
        customerAddButton.setCornerRadius(cornerRadius: 10)
        customerAddButton.backgroundColor = UIColor().buttonGreen
        favoriteTitleLabel.setText(text: LocalizeStrings.add_favoritelabel.localized, font: UIFont().subFont)
        favoriteAddButton.setCornerRadius(cornerRadius: 10)
        favoriteAddButton.setText(text: LocalizeStrings.add_button.localized, font: UIFont().bodyFont, textColor: .black)
        favoriteAddButton.backgroundColor = UIColor().buttonGreen
        searchButton.setCommonLayout(cornerRadius: 15, borderWidth: 2)
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
            present(Alert().setOnlyMessageAlert(message: LocalizeStrings.empty_name.localized), animated: true)
            return;
        }
        if isValidNumber(intakeTextField.text) != 0{
            if isValidNumber(intakeTextField.text) == 1{
                present(Alert().setOnlyMessageAlert(message: LocalizeStrings.empty_protein.localized), animated: true)
            }else {
                present(Alert().setOnlyMessageAlert(message: LocalizeStrings.error_number.localized), animated: true)
            }
            return;
        }
        
        if favoriteFlag == 1 {
            let favoriteProtein = Favorites(proteinName: proteinNameTextField.text!, proteinIntake: Int(intakeTextField.text!)!)
            if favoriteProteinRealm.filter("proteinName == '\(favoriteProtein.proteinName)'").count > 0 {
                present(Alert().setOnlyMessageAlert(message: LocalizeStrings.error_duplicate.localized), animated: true)
                return
            }else {
                try! localRealm.write {
                    localRealm.add(favoriteProtein)
                }
            }
        }
        let addProtein = DailyProtein(proteinName: proteinNameTextField.text!, proteinIntake: Int(intakeTextField.text!)!)
        try! localRealm.write {
            localRealm.add(addProtein)
            Storage.addTotalProtein(addProtein.proteinIntake)
            self.present(Alert().setAlert(title: LocalizeStrings.alert_addTitle.localized, message: LocalizeStrings.alert_addContent.localized), animated: false)
            intakeTextField.text = ""
            proteinNameTextField.text = ""
            favoriteSwitch.isOn = false
            favoriteFlag = 0
            favoriteTableView.reloadData()
        }
       
    }
    
    @IBAction func favoriteAddButtonClicked(_ sender: UIButton) {
        
        if favoriteName == nil || favoriteIntake == nil {
            present(Alert().setOnlyMessageAlert(message: LocalizeStrings.empty_favorite.localized), animated: true)

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
        cell.setText(name: row.proteinName, intake: "\(row.proteinIntake) g")
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
