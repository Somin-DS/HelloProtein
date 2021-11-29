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
    let shapeLayer = CAShapeLayer()
    
    @IBOutlet weak var rightBarButton: UIBarButtonItem!
    @IBOutlet weak var leftBarButton: UIBarButtonItem!
    @IBOutlet weak var intakeLabel: UILabel!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var showTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("locate-> \(localRealm.configuration.fileURL!)")


        
        showTableView.delegate = self
        showTableView.dataSource = self
        
        dailyProteinRealm = localRealm.objects(DailyProtein.self)
        statProteinRealm = localRealm.objects(StatProtein.self)
        
        Storage.addTotalProtein(0)
        
        title = "Today"

        
        let trackLayer = CAShapeLayer()
        let circularPath =  UIBezierPath(arcCenter: CGPoint(x: view.frame.size.width / 2.0 , y: view.frame.size.height / 3.5), radius: 120, startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true)

        trackLayer.path = circularPath.cgPath
        
        trackLayer.strokeColor = UIColor.lightGray.cgColor
        trackLayer.lineWidth = 20
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineCap = .round

        
        
        shapeLayer.path = circularPath.cgPath
        
        shapeLayer.strokeColor = UIColor.red.cgColor
        shapeLayer.lineWidth = 20
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineCap = .round
        shapeLayer.strokeEnd = 0
        
        view.layer.addSublayer(trackLayer)
        view.layer.addSublayer(shapeLayer)
        
        
    
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        showTableView.reloadData()
        
        let day = Date()
        if !isToday(day) {
            let yesterday = UserDefaults.standard.string(forKey: "date")!
            let yesterdayTotalProtein = UserDefaults.standard.integer(forKey: "totalIntake")

            Storage.saveDate(day)
            Storage.saveDailyTotal(yesterday, yesterdayTotalProtein)
            Storage.resetData()
            showTableView.reloadData()
        }
        intakeLabel.text = "\(UserDefaults.standard.integer(forKey: "totalIntake"))g / \(UserDefaults.standard.integer(forKey: "targetProtein"))g"
        handleTap(calculatePercentage())
    }
    func handleTap(_ percentage: Double) {
        print(#function)
        print(percentage)
        
        let basicAnimation = CABasicAnimation(keyPath: "strokeEnd")
        
        basicAnimation.toValue = percentage
        
        basicAnimation.duration = 2
        
        basicAnimation.fillMode = .forwards  //마지막에 멈추기
        basicAnimation.isRemovedOnCompletion = false
        shapeLayer.add(basicAnimation, forKey: "urSoBasic")
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
