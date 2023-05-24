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
    let name: String?
    let proteinContent: String?
    let name2: String?
    let proteinContent2: Double?
    
    enum CodingKeys: String, CodingKey {
        case name = "DESC_KOR"
        case proteinContent = "NUTR_CONT3"
        case name2 = "Food"
        case proteinContent2 = "Protein"
    }
}
