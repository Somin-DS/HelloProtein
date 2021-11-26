//
//  AddViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit

class AddViewController: UIViewController {

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var closeButtonText: String
        //test
        closeButtonText = "닫기"
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: closeButtonText, style: .plain, target: self, action: #selector(closeButtonClicked))
    }
    
    @objc func closeButtonClicked(){
        self.dismiss(animated: true, completion: nil)
    }
    
   
    @IBAction func searchButtonClicked(_ sender: UIButton) {
        
        let sb = UIStoryboard(name: "Add", bundle: nil)
        
        let vc = sb.instantiateViewController(withIdentifier: "SearchViewController")
        
        let nav = UINavigationController(rootViewController: vc)
        
        self.present(nav, animated: true, completion: nil)
        
    }
    
}
