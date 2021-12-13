//
//  Date.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/30.
//

import Foundation

struct DateForm {
    var startDate: Date
    var endDate: Date
    var startString: String
    var endString: String
}

func dateToString(_ date: Date?) -> String {
    
    if let date = date {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        return "\(year)-\(month)-\(day)"
    }
    return "0000-00-00"
}

func calculateDayBefore(_ date: Date) -> Date {

    let yesterday = Calendar.current.date(byAdding: .day, value: 1, to: date)
    
    return yesterday ?? Date()
}
