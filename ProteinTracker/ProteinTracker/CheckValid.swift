//
//  CheckValid.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/27.
//

import Foundation

func isValidNumber(_ text: String?) -> Int {

    guard let text = text else {
        return ErrorString.EmptyString.rawValue
    }
    
    if text.isEmpty { return ErrorString.EmptyString.rawValue}
    if Double(text) == nil { return ErrorString.NotNumber.rawValue}
    else if Double(text) == 0 { return ErrorString.Zero.rawValue}
    return 0
}

func isValidString(_ text: String?) -> Int {
    
    guard let text = text else {
        return ErrorString.EmptyString.rawValue
    }
    
    if text.isEmpty { return ErrorString.EmptyString.rawValue}
    
    return 0
}

func isToday(_ date: Date) -> Bool {

    let now = Date() // 현재의 Date (ex: 2020-08-13 09:14:48 +0000)
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd-EEE"// 2020-08-13 16:30
    var str = dateFormatter.string(from: now)// 현재 시간의 Date를 format에 맞춰 string으로 반환
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "date") == nil {
        UserDefaults.standard.set(str, forKey: "date")
        UserDefaults.standard.set(now, forKey: "Date")
        return true
    } else {
        var date = UserDefaults.standard.string(forKey: "date")!
        let tmpDate = date.split(separator: "-").map{String($0)}
        let tmpStr = str.split(separator: "-").map{String($0)}
        date = "\(tmpDate[0])-\(tmpDate[1])-\(tmpDate[2])"
        str = "\(tmpStr[0])-\(tmpStr[1])-\(tmpStr[2])"

        if date == str {
            return true
        }else {
            return false
        }
    }
}
