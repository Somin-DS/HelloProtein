//
//  InitViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import Toast
import TextFieldEffects

enum Activity: String {
    case light, moderate, active
}

class InitViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var weightTextField: UITextField!
    @IBOutlet weak var targetProteinTextField: UITextField!

    @IBOutlet weak var weightSegmentControl: UISegmentedControl!
    
    @IBOutlet weak var activityLabel: UILabel!
    
    @IBOutlet weak var activitySegmentControl: UISegmentedControl!
    
    @IBOutlet weak var recommendLabel: UILabel!
    
    @IBOutlet weak var recommendResultLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    
    var weightMeasure = "kg"
    var activityLevel = Activity.light
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        
        weightTextField.placeholder = LocalizeStrings.init_weightfield.localized
        targetProteinTextField.placeholder = LocalizeStrings.init_targetfield.localized
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
            
            recommendResultLabel.text = " \(calculateTargetProtein(weight, weightMeasure, activityLevel)) g"
            
        }else {
            
            if weightValid == ErrorString.EmptyString.rawValue {
                self.view.makeToast(LocalizeStrings.empty_weight.localized)
            }
            if weightValid == ErrorString.NotNumber.rawValue {
                self.view.makeToast(LocalizeStrings.error_number.localized)
            }
        }
    }
    
    @IBAction func startButtonClicked(_ sender: UIButton) {
        
        let valid = isValidNumber(targetProteinTextField.text)
        if valid == 0 {
            Storage.saveTargetProtein(targetProteinTextField.text!)
            let sb = UIStoryboard(name: "Show", bundle: nil)
            let vc = sb.instantiateViewController(withIdentifier: "ShowViewController") as! ShowViewController
            self.navigationController?.pushViewController(vc, animated: true)
        }else {
            if valid == ErrorString.EmptyString.rawValue {
                self.view.makeToast(LocalizeStrings.empty_protein.localized)
            }else {
                self.view.makeToast(LocalizeStrings.error_number.localized)
            }
        }
    }
}
