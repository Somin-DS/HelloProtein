//
//  ProteinInformation.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/27.
//

import Foundation

struct ProteinInformation {
    var name: String
    var intake: Int = 100
    var protein: Int
    var favorite: Int = 0
}

struct TotalProtein {
    var intake: Int
    var date: Date
}
