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

        showTableView.delegate = self
        showTableView.dataSource = self
        
        dailyProteinRealm = localRealm.objects(DailyProtein.self)
        statProteinRealm = localRealm.objects(StatProtein.self)
        
        Storage.addTotalProtein(0)
        
        showTableView.rowHeight = UITableView.automaticDimension
        showTableView.estimatedRowHeight = 44.0
        
        
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.font: UIFont().headFont]
        title = "Today"
        self.navigationController?.navigationBar.topItem?.title = "Today"
        self.navigationController?.navigationBar.tintColor = .black

        let trackLayer = CAShapeLayer()
        let circularPath =  UIBezierPath(arcCenter: CGPoint(x: view.frame.size.width / 2.0 , y: view.frame.size.height / 3.5), radius: 120, startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true)

        trackLayer.path = circularPath.cgPath
        
        trackLayer.strokeColor = UIColor.lightGray.cgColor
        trackLayer.lineWidth = 20
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineCap = .round
        
        shapeLayer.path = circularPath.cgPath
        
        shapeLayer.strokeColor = UIColor(red: 200.0/255.0, green: 244.0/255.0, blue: 194.0/255.0, alpha: 1.0).cgColor

        shapeLayer.lineWidth = 20
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineCap = .round
        shapeLayer.strokeEnd = 0
        
        view.layer.addSublayer(trackLayer)
        view.layer.addSublayer(shapeLayer)

        showTableView.layer.masksToBounds = true
        
        intakeLabel.numberOfLines = 0
        intakeLabel.textAlignment = .center
        intakeLabel.font = UIFont().subFont
        intakeLabel.layer.cornerRadius = 20
        intakeLabel.layer.masksToBounds = true
        
        addButton.tintColor = .black
        
        rightBarButton.image = UIImage(systemName: "gearshape.fill")
        rightBarButton.tintColor = .black
        
        leftBarButton.image = UIImage(systemName: "chart.bar.xaxis")
        leftBarButton.tintColor = .black
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        showTableView.reloadData()
        
        let day = Date()
        if !isToday(day) {
            let yesterday = UserDefaults.standard.string(forKey: "date")
            let yesterdayDate = UserDefaults.standard.object(forKey: "Date")
            let yesterdayTotalProtein = UserDefaults.standard.integer(forKey: "totalIntake")

            Storage.saveDate(day)
            Storage.saveDailyTotal(yesterday, yesterdayDate as? Date , yesterdayTotalProtein)
            Storage.resetData()
            showTableView.reloadData()
        }
        intakeLabel.text = "\(UserDefaults.standard.integer(forKey: "totalIntake"))g / \(UserDefaults.standard.integer(forKey: "targetProtein"))g"
        drawCircle(calculatePercentage())
    }
    func drawCircle(_ percentage: Double) {

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
        cell.nameLabel.textAlignment = .center
        cell.nameLabel.numberOfLines = 0
        cell.nameLabel.font = UIFont().bodyFont
        
        cell.nameLabel.numberOfLines = 0
        cell.nameLabel.lineBreakMode = .byWordWrapping
        
        cell.intakeLabel.numberOfLines = 0
        cell.intakeLabel.lineBreakMode = .byWordWrapping
        cell.intakeLabel.text = "\(row.proteinIntake)g"
        cell.intakeLabel.textAlignment = .center
        cell.intakeLabel.numberOfLines = 0
        cell.intakeLabel.font = UIFont().bodyFont
        
        return cell
    }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        
        try! localRealm.write {
            let deleteProtein = dailyProteinRealm[indexPath.row].proteinIntake
            localRealm.delete(dailyProteinRealm[indexPath.row])
            Storage.subtractTotalProtein(deleteProtein)
            showTableView.reloadData()
            intakeLabel.text = "\(UserDefaults.standard.integer(forKey: "totalIntake"))g / \(UserDefaults.standard.integer(forKey: "targetProtein"))g"
            drawCircle(calculatePercentage())
        }
    }
    
    
}
