//
//  InitViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class InitViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        getLanguageSetting()
    }
    
    //기기 언어 설정값 가져오기
    func getLanguageSetting(){
        let localeID = Locale.preferredLanguages.first
        let deviceLocale = (Locale(identifier: localeID!).languageCode)!
        print(deviceLocale)
    }
    

    @IBAction func startButtonClicked(_ sender: UIButton) {
        
        let sb = UIStoryboard(name: "Show", bundle: nil)
        let vc = sb.instantiateViewController(withIdentifier: "ShowViewController") as! ShowViewController
        let nav = UINavigationController(rootViewController: vc)
        vc.modalPresentationStyle = .fullScreen
        present(nav, animated: false, completion: nil)
    }
}
