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
    
    return 0
}
