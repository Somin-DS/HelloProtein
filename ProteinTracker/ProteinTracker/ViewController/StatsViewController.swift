//
//  StatsViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import Charts
import RealmSwift

class StatsViewController: UIViewController {

    @IBOutlet weak var barChartView: BarChartView!
    @IBOutlet weak var backgroundView: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var averageLabel: UILabel!
    let localRealm = try! Realm()
    lazy var statRealm = localRealm.objects(StatProtein.self)
    var setWeeks: [String] = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    let calendar: Calendar = Calendar.current
    lazy var values = addChartData()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        setUI()
        setChart()

    }
    
    func setUI() {
        title = "Stats"
        navigationItem.backButtonTitle = ""
        navigationItem.backBarButtonItem?.tintColor = .black
        titleLabel.setText(text: LocalizeStrings.stats_averagelabel.localized, font: UIFont().bodyFont)
        titleLabel.textAlignment = .center
        averageLabel.setCommonLable(font: UIFont().headFont)
        averageLabel.setCornerRadius(cornerRadius: 20)
        averageLabel.text = "\(calculateAverageProtein(values)) g"
        backgroundView.setCornerRadius(cornerRadius: 20)
        barChartView.setCornerRadius(cornerRadius: 10)
        barChartView.noDataText = LocalizeStrings.stats_empty.localized
        barChartView.noDataFont = UIFont().bodyFont
        barChartView.noDataTextColor = .lightGray
        barChartView.backgroundColor = .white
    }
    
    func setChart(){
        if values.isEmpty {
            return ;
        }
        
        var dataEntries: [BarChartDataEntry] = []
        for i in 0..<setWeeks.count {
            let dataEntry = BarChartDataEntry(x: Double(i), y: values[i])
            dataEntries.append(dataEntry)
        }
        //Double -> Int로 formatter
        let valFormatter = NumberFormatter()
        valFormatter.numberStyle = .currency
        valFormatter.maximumFractionDigits = 2
        valFormatter.currencySymbol = "$"
        
        let format = NumberFormatter()
        format.numberStyle = .none
        let formatter = DefaultValueFormatter(formatter: format)
        
        //target
//        let targetProtein = Int(UserDefaults.standard.string(forKey: "targetProtein") ?? "0")
//        let target = ChartLimitLine(limit: Double(targetProtein!))
        
        let chartDataSet = BarChartDataSet(entries: dataEntries, label: "Weekly")
        chartDataSet.valueFont = UIFont().bodyFont
        chartDataSet.axisDependency = .right
        let charData =  BarChartData(dataSet: chartDataSet)
        
        
        charData.setValueFormatter(formatter)
        barChartView.leftAxis.valueFormatter = DefaultAxisValueFormatter(formatter: valFormatter)
        barChartView.data = charData
//        barChartView.leftAxis.addLimitLine(target)
        barChartView.leftAxis.labelFont = UIFont().bodyFont
        
       
        chartDataSet.highlightEnabled = false

        chartDataSet.colors = [NSUIColor(cgColor: UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0).cgColor)]
        barChartView.doubleTapToZoomEnabled = false
        
        // X축 레이블 위치 조정
        barChartView.xAxis.labelPosition = .bottom
        // X축 레이블 포맷 지정
        barChartView.xAxis.valueFormatter = IndexAxisValueFormatter(values: setWeeks)
        barChartView.xAxis.setLabelCount(7, force: false)
        // 오른쪽 레이블 제거
        barChartView.rightAxis.enabled = false
        barChartView.leftAxis.enabled = false
        barChartView.fitBars = true
        barChartView.xAxis.gridColor = .clear
        barChartView.legend.enabled = false
        barChartView.xAxis.labelFont = UIFont().bodyFont
        barChartView.extraBottomOffset = 20

    }

    func addChartData() -> [Double] {

        let weeksEnSet: [String] = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        let weeksKoSet: [String] = ["월", "화", "수", "목", "금", "토", "일"]
        
        
        //요일 dataset
        var dataSet: [Double] = Array(repeating: 0, count: weeksEnSet.count)
        
        // "2021-11-18-Fri" / "2021-11-18-금" , 50
        let calendar = Calendar.current
        var startOfWeek = Date()
        for i in statRealm.reversed() {
            startOfWeek = calendar.startOfWeek(i.originDate)
            break
        }
        let currentStartOfWeek = calendar.startOfWeek(Date())
        if  dateToString(currentStartOfWeek) != dateToString(startOfWeek) {
            return dataSet
        }
        for i in statRealm.reversed() {
            let tempStartOfWeek = calendar.startOfWeek(i.originDate)

            if dateToString(startOfWeek) != dateToString(tempStartOfWeek) {
                break
            }
            let dateArray = i.date.split(separator: "-").map{String($0)}
            let day = dateArray[3]
            
            if weeksEnSet.contains(day) {
                dataSet[weeksEnSet.firstIndex(of: day)!] = Double(i.totalIntake)
            }else {
                dataSet[weeksKoSet.firstIndex(of: day)!] = Double(i.totalIntake)
            }
        }
 
        return dataSet
    }
    
}
