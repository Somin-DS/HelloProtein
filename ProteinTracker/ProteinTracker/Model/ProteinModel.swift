//
//  ProteinModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/04/09.
//

import Foundation

struct APIData: Codable {
    let I2790: Row
}

struct Row: Codable {
    let row: [Food]
}

struct Food: Codable {
    let name: String
    let proteinContent: String
    
    enum CodingKeys: String, CodingKey {
        case name = "DESC_KOR"
        case proteinContent = "NUTR_CONT3"
    }
}
