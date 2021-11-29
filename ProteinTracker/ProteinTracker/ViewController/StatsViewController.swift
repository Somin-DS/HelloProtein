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
    var statRealm: Results<StatProtein>!
    var setWeeks: [String]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print(#function)
        
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
       
        title = "Stats"
        titleLabel.text = LocalizeStrings.stats_averagelabel.localized
        
        statRealm = localRealm.objects(StatProtein.self)
        setWeeks = []
        
        barChartView.noDataText = LocalizeStrings.stats_empty.localized
        barChartView.noDataTextColor = .lightGray
        
        let values = addChartData()
        setChart(values)
        
        averageLabel.text = "\(calculateAverageProtein(values)) g"
        
    }
    
    func setChart(_ Values: [Double]){
        
        print("setWeeks:\(setWeeks ?? [])")
        if setWeeks.count == 0 {
            return ;
        }
        var Values = Values
        setWeeks.reverse()
        Values.reverse()
        var dataEntries: [BarChartDataEntry] = []
        for i in 0..<setWeeks.count {
            let dataEntry = BarChartDataEntry(x: Double(i), y: Values[i])
            dataEntries.append(dataEntry)
        }
        
        let chartDataSet = BarChartDataSet(entries: dataEntries)
        
        chartDataSet.colors = [.blue]
        
        let charData =  BarChartData(dataSet: chartDataSet)
        barChartView.data = charData
        
        chartDataSet.highlightEnabled = false
        barChartView.doubleTapToZoomEnabled = false
        
        // X축 레이블 위치 조정
        barChartView.xAxis.labelPosition = .bottom
        // X축 레이블 포맷 지정
        barChartView.xAxis.valueFormatter = IndexAxisValueFormatter(values: setWeeks)
        barChartView.xAxis.setLabelCount(7, force: false)
        // 오른쪽 레이블 제거
        barChartView.rightAxis.enabled = false
    }

    func addChartData() -> [Double] {

        print(#function)
        let weeksEnSet: [String] = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        let weeksKoSet: [String] = ["월", "화", "수", "목", "금", "토", "일"]
        
        if statRealm.count == 0 {
            return []
        }
        
        //요일 dataset
        var dataSet: [Double] = []
        
        // "2021-11-18-Fri" / "2021-11-18-금" , 50
        for i in statRealm.reversed() {
            let dateArray = i.date.split(separator: "-").map{String($0)}
            let day = dateArray[3]
            //"Fri" or "금"
            print("day: \(day)")
            if weeksEnSet.contains(day) {
                setWeeks.append(day)
            }else {
                setWeeks.append(weeksEnSet[weeksKoSet.firstIndex(of: day)!])
            }
            print("protein:\(i.totalIntake)")
            dataSet.append(Double(i.totalIntake))
            if setWeeks.count > 6 {
                break
            }
        }
        return dataSet
    }
    func calculateAverageProtein(_ values: [Double]) -> String {
        
        var totalProtein: Double = 0
        var count = 0
        for i in values {
            if i != 0 {
                totalProtein += i
                count += 1
            }
        }
        
        if totalProtein == 0 {
            return "0"
        }
        return  String(format: "%.1f", (totalProtein / Double(count)))
    }

}
