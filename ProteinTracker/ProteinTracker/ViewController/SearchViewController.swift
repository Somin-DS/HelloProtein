//
//  SearchViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/25.
//

import UIKit

class SearchViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeButtonClicked))
    }
                                                            
    @objc func closeButtonClicked() {
        self.dismiss(animated: true, completion: nil)
    }
    

}
