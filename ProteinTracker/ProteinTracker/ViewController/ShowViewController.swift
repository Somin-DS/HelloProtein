//
//  ShowViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import RealmSwift

class ShowViewController: UIViewController {

    let localRealm = try! Realm()
    var dailyProteinRealm: Results<DailyProtein>!
    var statProteinRealm: Results<StatProtein>!
    
    @IBOutlet weak var rightBarButton: UIBarButtonItem!
    @IBOutlet weak var leftBarButton: UIBarButtonItem!
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var showImageView: UIImageView!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var showTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        showTableView.delegate = self
        showTableView.dataSource = self
        
        dailyProteinRealm = localRealm.objects(DailyProtein.self)
        statProteinRealm = localRealm.objects(StatProtein.self)
        
        Storage.addTotalProtein(0)
        
        intakeLabel.text = "\(UserDefaults.standard.integer(forKey: "totalIntake")) g"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        showTableView.reloadData()
        
        intakeLabel.text = String(UserDefaults.standard.integer(forKey: "totalIntake"))
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
    }
    
    //Add View로 전환(show modally)
    @IBAction func addButtonClicked(_ sender: UIButton) {
        
        //1.
        let sb = UIStoryboard(name: "Add", bundle: nil)
        
        let vc = sb.instantiateViewController(withIdentifier: "AddViewController")

        let nav = UINavigationController(rootViewController: vc)
        
        nav.modalPresentationStyle = .fullScreen
        self.present(nav, animated: true, completion: nil)
        
    }

}

extension ShowViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dailyProteinRealm.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ShowTableViewCell.identifier, for: indexPath) as? ShowTableViewCell else { return UITableViewCell() }
        
        let row = dailyProteinRealm[indexPath.row]
        
        cell.nameLabel.text = row.proteinName
        cell.intakeLabel.text = String(row.proteinIntake)
        
        return cell
    }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        
        try! localRealm.write {
            let deleteProtein = dailyProteinRealm[indexPath.row].proteinIntake
            localRealm.delete(dailyProteinRealm[indexPath.row])
            Storage.subtractTotalProtein(deleteProtein)
            showTableView.reloadData()
            intakeLabel.text = String(UserDefaults.standard.integer(forKey: "totalIntake"))
        }
    }
    
    
}
