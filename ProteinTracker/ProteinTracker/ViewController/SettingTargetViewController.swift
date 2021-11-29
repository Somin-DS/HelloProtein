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

    
    @IBOutlet weak var weightTextField: UITextField!
    @IBOutlet weak var targetProteinTextField: UITextField!

    @IBOutlet weak var weightSegmentControl: UISegmentedControl!
    
    @IBOutlet weak var activityLabel: UILabel!
    
    @IBOutlet weak var activitySegmentControl: UISegmentedControl!
    
    
    @IBOutlet weak var recommendResultLabel: UILabel!
    @IBOutlet weak var editButton: UIButton!
    
    var weightMeasure = "kg"
    var activityLevel = Activity.light
    
    override func viewDidLoad() {
        super.viewDidLoad()

        weightTextField.placeholder = LocalizeStrings.init_weightfield.localized
        targetProteinTextField.placeholder = LocalizeStrings.init_targetfield.localized
        
    }

    @IBAction func addTapGesture(_ sender: UITapGestureRecognizer) {
        view.endEditing(true)
    }
    
    @IBAction func weightSegmentSelected(_ sender: UISegmentedControl) {
        
        if sender.selectedSegmentIndex == 0 {
            weightMeasure = "kg"
        }else {
            weightMeasure = "lb"
        }
    }
    
    @IBAction func activitySegmentSelected(_ sender: UISegmentedControl) {
        
        if sender.selectedSegmentIndex == 0 {
            activityLevel = Activity.light
        } else if sender.selectedSegmentIndex == 1 {
            activityLevel = Activity.moderate
        } else {
            activityLevel = Activity.active
        }
    }
    
    @IBAction func calculButtonClicked(_ sender: UIButton) {
        
       
        let weightValid = isValidNumber(weightTextField.text)
        
        if weightValid == 0 {
            let weight = Double(weightTextField.text!)!
            
            recommendResultLabel.text = String(format: NSLocalizedString("init_recommendlabel", comment: ""), calculateTargetProtein(weight, weightMeasure, activityLevel))
            
        }else {
            
            if weightValid == ErrorString.EmptyString.rawValue {
                self.view.makeToast(LocalizeStrings.empty_weight.localized)
            }
            if weightValid == ErrorString.NotNumber.rawValue {
                self.view.makeToast(LocalizeStrings.error_number.localized)
            }
        }
    }
    
    @IBAction func editButtonClicked(_ sender: UIButton) {
        
        let valid = isValidNumber(targetProteinTextField.text)
        if valid == 0 {
            Storage.saveTargetProtein(targetProteinTextField.text)
            let alert = UIAlertController(title: LocalizeStrings.alert_editTitle.localized, message: LocalizeStrings.alert_editContent.localized, preferredStyle: .alert)
            
            let cancelAction = UIAlertAction(title: LocalizeStrings.close_button.localized, style: .cancel, handler: nil)
            alert.addAction(cancelAction)
            self.present(alert, animated: false)
        }else {
            if valid == ErrorString.EmptyString.rawValue {
                self.view.makeToast(LocalizeStrings.empty_protein.localized)
            }else if valid == ErrorString.NotNumber.rawValue{
                self.view.makeToast(LocalizeStrings.error_number.localized)
            }else {
                self.view.makeToast(LocalizeStrings.error_zero.localized)
            }
        }
    }
}
