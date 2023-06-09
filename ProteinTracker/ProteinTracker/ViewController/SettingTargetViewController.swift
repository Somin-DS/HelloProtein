//
//  SettingTargetViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/29.
//

import UIKit
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

        setDelegate()
        configurePickerView()
        setUI()
        title = "Daily Target"
   
    }
    
    func setDelegate() {
        weightPickerView.delegate = self
        weightPickerView.dataSource = self
        activityPickerView.delegate = self
        activityPickerView.dataSource = self
        activityTextField.delegate = self
    }
    
    func configurePickerView() {
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
    }

    func setUI() {
        calculatorView.setCornerRadius(cornerRadius: 20)
        calculateButton.setCornerRadius(cornerRadius: 15)
        calculateButton.backgroundColor = UIColor().buttonGreen
        recommendResultLabel.setCornerRadius(cornerRadius: 20)
        recommendResultLabel.setText(text: "", font: UIFont().bodyFont)
        recommendResultLabel.numberOfLines = 0
        recommendResultLabel.backgroundColor = .white
        calculateButton.setButtonColorText(text: LocalizeStrings.init_callabel.localized, font: UIFont().bodyFont, textColor: .black)
        calculatorTitleLabel.setText(text: LocalizeStrings.init_cacultitle.localized, font: UIFont().subFont)
        weightTitleLabel.setCommonLayout(cornerRadius: 10, borderWidth: 2)
        weightTitleLabel.setText(text: LocalizeStrings.init_weigthTitle.localized, font: UIFont().labelFont)
        activityTitleLabel.setCommonLayout(cornerRadius: 10, borderWidth: 2)
        activityTitleLabel.setText(text: LocalizeStrings.init_activelabel.localized, font: UIFont().labelFont)
        weightTextField.setCommonLayout(cornerRadius: 10, borderWidth: 2)
        weightTextField.setText(placeholder: LocalizeStrings.init_weightfield.localized, font: UIFont().strFont, textAlignment: .center)
        activityTextField.setCommonLayout(cornerRadius: 10, borderWidth: 2)
        activityTextField.setText(placeholder: LocalizeStrings.init_activityfield.localized, font: UIFont().strFont, textAlignment: .center)
        targetProteinTextField.setCommonLayout(cornerRadius: 10, borderWidth: 2)
        targetProteinTextField.setText(placeholder: LocalizeStrings.init_targetfield.localized, font: UIFont().bodyFont, textAlignment: .center)
        editButton.setButtonColorText(text: LocalizeStrings.setting_edit.localized, font: UIFont().bodyFont, textColor: .black)
        editButton.setCornerRadius(cornerRadius: 25)
        editButton.backgroundColor = UIColor().buttonGreen

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
            if weightValid == ErrorString.EmptyString.rawValue {
                present(Alert().setOnlyMessageAlert(message: LocalizeStrings.empty_weight.localized), animated: true,completion: nil)
            }
            if weightValid == ErrorString.NotNumber.rawValue {
                present(Alert().setOnlyMessageAlert(message: LocalizeStrings.error_number.localized), animated: true,completion: nil)
            }
        }    }
    
    @IBAction func editButtonClicked(_ sender: UIButton) {
        
        let valid = isValidNumber(targetProteinTextField.text)
        switch valid {
        case ErrorString.EmptyString.rawValue:
            present(Alert().setOnlyMessageAlert(message: LocalizeStrings.empty_protein.localized), animated: true,completion: nil)
        case ErrorString.NotNumber.rawValue:
            present(Alert().setOnlyMessageAlert(message: LocalizeStrings.error_number.localized), animated: true,completion: nil)
        case ErrorString.Zero.rawValue:
            present(Alert().setOnlyMessageAlert(message: LocalizeStrings.error_zero.localized), animated: true,completion: nil)
        default:
            Storage.saveTargetProtein(targetProteinTextField.text)
            let alert = UIAlertController(title: LocalizeStrings.alert_editTitle.localized, message: LocalizeStrings.alert_editContent.localized, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: LocalizeStrings.close_button.localized, style: .cancel, handler: nil)
            alert.addAction(cancelAction)
            self.present(alert, animated: false)
        }
    }
}
extension SettingTargetViewController: UITextFieldDelegate {
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
