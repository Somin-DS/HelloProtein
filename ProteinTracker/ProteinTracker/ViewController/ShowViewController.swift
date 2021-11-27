//
//  ShowViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import Hero

class ShowViewController: UIViewController {

    
    @IBOutlet weak var rightBarButton: UIBarButtonItem!
    @IBOutlet weak var leftBarButton: UIBarButtonItem!
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var showImageView: UIImageView!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var showTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    
    //Setting View로 전환 (push)
    @IBAction func rightBarButtonClicked(_ sender: UIBarButtonItem) {
        
        let sb = UIStoryboard(name: "Setting", bundle: nil)
        
        let vc = sb.instantiateViewController(withIdentifier: "SettingViewController") as! SettingViewController
        
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    //Stats View로 전환(push)
    @IBAction func leftBarButtonClicked(_ sender: UIBarButtonItem) {
        
        let sb = UIStoryboard(name: "Stats", bundle: nil)
        
        let vc = sb.instantiateViewController(withIdentifier: "StatsViewController")
        
        self.navigationController?.pushViewController(vc, animated: true)

//        vc.hero.isEnabled = true
//        vc.hero.modalAnimationType = .selectBy(presenting: .push(direction: .right), dismissing: .push(direction: .left))
//
//        vc.heroModalAnimationType = .selectBy(presenting: .pull(direction: .left), dismissing: .slide(direction: .down))
    }
    
    //Add View로 전환(show modally)
    
    @IBAction func addButtonClicked(_ sender: UIButton) {
        
        //1.
        let sb = UIStoryboard(name: "Add", bundle: nil)
        
        let vc = sb.instantiateViewController(withIdentifier: "AddViewController")

        let nav = UINavigationController(rootViewController: vc)
        
        self.present(nav, animated: true, completion: nil)
        
        
    }
    

}
