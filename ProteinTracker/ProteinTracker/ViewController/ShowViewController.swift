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
    lazy var dailyProteinRealm = localRealm.objects(DailyProtein.self)
    lazy var statProteinRealm = localRealm.objects(StatProtein.self)
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
        
        setupUI()
        
        Storage.addTotalProtein(0) // Q - 0을 왜 더해줬지???
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        //테이블뷰 새로고침(추가했을 경우니까)
        showTableView.reloadData()
        
        // 하루지났을 경우 단백질 초기화
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
        
        //섭취 단백질량 텍스트
        intakeLabel.text = "\(UserDefaults.standard.integer(forKey: "totalIntake"))g / \(UserDefaults.standard.integer(forKey: "targetProtein"))g"
        
        //원형그래프 애니메이션
        drawCircle(calculatePercentage())
    }
    
    func setupUI() {
        
        setCircle()
        
        //타이틀 레이아웃
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.font: UIFont().headFont]
        self.navigationController?.navigationBar.topItem?.title = "Today" //Q - 이거 왜 두개냐
        self.navigationController?.navigationBar.tintColor = .black

        intakeLabel.setCommonLable(font: UIFont().subFont)
        intakeLabel.setCornerRadius(cornerRadius: 20)
        // 버튼 ui
        addButton.tintColor = .black
        
        //설정버튼 ui
        setupButtonUI(barButton: rightBarButton, imageName: "gearshape.fill", color: .black)
        setupButtonUI(barButton: leftBarButton, imageName: "chart.bar.xaxis", color: .black)
    
    }
    
    func setCircle() {
        // 원형그래프 그리기
        let trackLayer = CAShapeLayer()
        let circularPath =  UIBezierPath(arcCenter: CGPoint(x: view.frame.size.width / 2.0 , y: view.frame.size.height / 3.5), radius: 120, startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true)
        
        configureShapeLayer(layer: trackLayer, path: circularPath.cgPath, strokeColor: UIColor.lightGray.cgColor, lineWidth: 20, filColor: UIColor.clear.cgColor, lineCap: .round, strokeEnd: nil)
        configureShapeLayer(layer: shapeLayer, path: circularPath.cgPath, strokeColor: UIColor(red: 200.0/255.0, green: 244.0/255.0, blue: 194.0/255.0, alpha: 1.0).cgColor, lineWidth: 20, filColor: UIColor.clear.cgColor, lineCap: .round, strokeEnd: 0)
        
        view.layer.addSublayer(trackLayer)
        view.layer.addSublayer(shapeLayer)
    }
    
    func setTableViewUI() {
        //테이블뷰 레이아웃
        showTableView.layer.masksToBounds = true
        // Q - 이건 왜 한거지...?
        showTableView.rowHeight = UITableView.automaticDimension
        showTableView.estimatedRowHeight = 44.0
    }
    
    func configureShapeLayer(layer: CAShapeLayer, path: CGPath, strokeColor: CGColor, lineWidth: CGFloat, filColor: CGColor, lineCap: CAShapeLayerLineCap, strokeEnd: CGFloat?) {
        layer.path = path
        layer.strokeColor = strokeColor
        layer.lineWidth = lineWidth
        layer.fillColor = filColor
        layer.lineCap = lineCap
        if let strokeEnd {
            layer.strokeEnd = strokeEnd
        }
    }
    
    func setupButtonUI(barButton: UIBarButtonItem, imageName: String, color: UIColor){
        barButton.image = UIImage(systemName: imageName)
        barButton.tintColor = color
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
        cell.setText(name: row.proteinName, intake: "\(row.proteinIntake)g")
        return cell
    }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        
        //swipe시 테이블뷰에서 삭제
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
