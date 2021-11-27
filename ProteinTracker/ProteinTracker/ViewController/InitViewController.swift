//
//  InitViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class InitViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var heightTextField: UITextField!
    @IBOutlet weak var weightTextField: UITextField!
    @IBOutlet weak var targetProteinTextField: UITextField!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        getLanguageSetting()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }
    
    
    func saveTargetProtein(_ protein: String?){
        UserDefaults.standard.set(protein, forKey: "targetProtein")
    }
    //기기 언어 설정값 가져오기
    func getLanguageSetting(){
        let localeID = Locale.preferredLanguages.first
        let deviceLocale = (Locale(identifier: localeID!).languageCode)!
        print(deviceLocale)
    }
    
    @IBAction func startButtonClicked(_ sender: UIButton) {
        
        print(#function)
        if let target = targetProteinTextField.text, !target.isEmpty {
            saveTargetProtein(target)
            let sb = UIStoryboard(name: "Show", bundle: nil)
            let vc = sb.instantiateViewController(withIdentifier: "ShowViewController") as! ShowViewController
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            print("목표 단백질을 입력해주세요")
        }
        
    }
}
