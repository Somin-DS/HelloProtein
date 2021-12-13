//
//  SettingTargetViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/29.
//

import UIKit
import Toast
import TextFieldEffects


class SettingTargetViewController: UIViewController {

    
    @IBOutlet weak var calculatorTitleLabel: UILabel!
    @IBOutlet weak var weightTextField: UITextField!
    @IBOutlet weak var targetProteinTextField: UITextField!

    @IBOutlet weak var weightTitleLabel: UILabel!
    
    @IBOutlet weak var activityTitleLabel: UILabel!
    @IBOutlet weak var activityTextField: UITextField!
    @IBOutlet weak var calculateButton: UIButton!
    
    @IBOutlet weak var recommendResultLabel: UILabel!
    @IBOutlet weak var editButton: UIButton!
    
    @IBOutlet weak var calculatorView: UIView!
    
    
    var weightMeasure = "kg"
    var activityLevel = "Light"
    let weightRange = Array(1...800).map{String($0)}
    let weightUnit = ["kg", "lb"]
    let activityRange = [LocalizeStrings.init_segone.localized, LocalizeStrings.init_segtwo.localized, LocalizeStrings.init_segthree.localized]
    let weightPickerView = UIPickerView()
    let activityPickerView = UIPickerView()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        
        
        weightPickerView.delegate = self
        activityPickerView.delegate = self
        weightPickerView.dataSource = self
        activityPickerView.dataSource = self
        activityTextField.delegate = self
        
        title = "Daily Target"
        
        self.weightTextField.inputView = weightPickerView
        self.activityTextField.inputView = activityPickerView
        
        let toolBar = UIToolbar()
        toolBar.frame = CGRect(x: 0, y: 0, width: 0, height: 40)
        toolBar.backgroundColor = .darkGray
        self.weightTextField.inputAccessoryView = toolBar
        self.activityTextField.inputAccessoryView = toolBar
        
        let barButton = UIBarButtonItem()
        barButton.title = LocalizeStrings.init_barbutton.localized
        barButton.target = self
        barButton.action = #selector(doneButtonClicked(_:))
        
        let space = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        
        toolBar.setItems([space, barButton], animated: true)
        
        calculatorView.layer.cornerRadius = 20
        calculatorView.layer.masksToBounds = true
        calculatorTitleLabel.text = LocalizeStrings.init_cacultitle.localized
        calculatorTitleLabel.font = UIFont().subFont
        
        
        weightTitleLabel.text = LocalizeStrings.init_weigthTitle.localized
        weightTitleLabel.font = UIFont().labelFont
        weightTitleLabel.backgroundColor = .white
        weightTitleLabel.layer.masksToBounds = true
        weightTitleLabel.layer.cornerRadius = 10
        weightTitleLabel.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        weightTitleLabel.layer.borderWidth = 2
        
        activityTitleLabel.text = LocalizeStrings.init_activelabel.localized
        activityTitleLabel.font = UIFont().labelFont
        activityTitleLabel.backgroundColor = .white
        activityTitleLabel.layer.masksToBounds = true
        activityTitleLabel.layer.cornerRadius = 10
        activityTitleLabel.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        activityTitleLabel.layer.borderWidth = 2
        
        weightTextField.placeholder = LocalizeStrings.init_weightfield.localized
        weightTextField.textAlignment = .center
        weightTextField.font = UIFont().strFont
        weightTextField.backgroundColor = .white
        weightTextField.layer.masksToBounds = true
        weightTextField.layer.cornerRadius = 10
        weightTextField.layer.borderWidth = 2
        weightTextField.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        
        activityTextField.placeholder = LocalizeStrings.init_activityfield.localized
        activityTextField.textAlignment = .center
        activityTextField.font = UIFont().strFont
        activityTextField.backgroundColor = .white
        activityTextField.layer.masksToBounds = true
        activityTextField.layer.cornerRadius = 10
        activityTextField.layer.borderWidth = 2
        activityTextField.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        
        
        targetProteinTextField.placeholder = LocalizeStrings.init_targetfield.localized
        targetProteinTextField.textAlignment = .center
        targetProteinTextField.font = UIFont().bodyFont
        targetProteinTextField.backgroundColor = .white
        targetProteinTextField.layer.masksToBounds = true
        targetProteinTextField.layer.cornerRadius = 10
        targetProteinTextField.layer.borderWidth = 2
        targetProteinTextField.layer.borderColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor
        

        
        editButton.tintColor = .black
        editButton.setTitle(LocalizeStrings.setting_edit.localized, for: .normal)
        editButton.titleLabel?.font = UIFont().bodyFont
        editButton.layer.masksToBounds = true
        editButton.layer.cornerRadius = 25
        editButton.backgroundColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 0.8)
        
        calculateButton.tintColor = .black
        calculateButton.setTitle(LocalizeStrings.init_callabel.localized, for: .normal)
        calculateButton.titleLabel?.font = UIFont().bodyFont
        calculateButton.layer.masksToBounds = true
        calculateButton.layer.cornerRadius = 15
        calculateButton.backgroundColor = UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 0.8)
        
        recommendResultLabel.textAlignment = .center
        recommendResultLabel.text = ""
        recommendResultLabel.numberOfLines = 0
        recommendResultLabel.font = UIFont().bodyFont
        recommendResultLabel.layer.masksToBounds = true
        recommendResultLabel.backgroundColor = .white
        recommendResultLabel.layer.cornerRadius = 20
   
        
    }

    @objc func doneButtonClicked(_ sender: Any) {
        self.view.endEditing(true)
    }
    
    
    @IBAction func addTapGesture(_ sender: UITapGestureRecognizer) {
        view.endEditing(true)
    }
    
    
    @IBAction func calculButtonClicked(_ sender: UIButton) {
        
       
        let weightValid = isValidNumber(weightTextField.text)
        
        if weightValid == 0 {
            let weight = Double(weightTextField.text!)!
            var activity: Activity
            if activityLevel == "Light" || activityLevel == "적음" {
                activity = Activity.light
            }else if activityLevel == "Moderate" || activityLevel == "보통" {
                activity = Activity.moderate
            }else {
                activity = Activity.active
            }
            let recommendProtein = calculateTargetProtein(weight, weightMeasure, activity)
            recommendResultLabel.text = String(format: NSLocalizedString("init_recommendlabel", comment: ""), recommendProtein)
            targetProteinTextField.text = String(Int(Double(recommendProtein) ?? 0.0))
            
        }else {
            let windows = UIApplication.shared.windows
            if weightValid == ErrorString.EmptyString.rawValue {
                
                windows.last?.makeToast(LocalizeStrings.empty_weight.localized)
            }
            if weightValid == ErrorString.NotNumber.rawValue {
                windows.last?.makeToast(LocalizeStrings.error_number.localized)
            }
        }
    }
    
    @IBAction func editButtonClicked(_ sender: UIButton) {
        
        let windows = UIApplication.shared.windows
        let valid = isValidNumber(targetProteinTextField.text)
        if valid == 0 {
            Storage.saveTargetProtein(targetProteinTextField.text)
            let alert = UIAlertController(title: LocalizeStrings.alert_editTitle.localized, message: LocalizeStrings.alert_editContent.localized, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: LocalizeStrings.close_button.localized, style: .cancel, handler: nil)
            alert.addAction(cancelAction)
            self.present(alert, animated: false)
        }else {
            if valid == ErrorString.EmptyString.rawValue {
                windows.last?.makeToast(LocalizeStrings.empty_protein.localized)
//                self.view.makeToast(LocalizeStrings.empty_protein.localized)
            }else if valid == ErrorString.NotNumber.rawValue{
                windows.last?.makeToast(LocalizeStrings.error_number.localized)
//                self.view.makeToast(LocalizeStrings.error_number.localized)
            }else {
                windows.last?.makeToast(LocalizeStrings.error_zero.localized)
//                self.view.makeToast(LocalizeStrings.error_zero.localized)
            }
        }
    }
}
extension SettingTargetViewController: UITextFieldDelegate {
//    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//        guard let text = textField.text else { return true }
//        let newLength = text.count + string.count - range.length
//        return newLength <= 4
//    }
    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.activityTextField.text = activityRange[0]
    }
}

extension SettingTargetViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        if pickerView == weightPickerView {
            return 2
        }else {
            return 1
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView == weightPickerView {
            if component == 0{
                return weightUnit.count
            }else {
                return weightRange.count
            }
        }else {
            return activityRange.count
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView == weightPickerView {
            if component == 0 {
                weightMeasure = weightUnit[row]
            }else {
                self.weightTextField.text = "\(self.weightRange[row])"
            }
        }else {
            activityLevel = activityRange[row]
            self.activityTextField.text = "\(self.activityRange[row])"
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView == weightPickerView {
            if component == 0 {
                return weightUnit[row]
            }else {
                return weightRange[row]
            }
        }else {
            return activityRange[row]
        }
    }
}
