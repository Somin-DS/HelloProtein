//
//  UIColor+Extension.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/04/08.
//

import UIKit

extension UIColor {
    var mainGreen: UIColor {
        return UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 1.0)
    }
    var buttonGreen: UIColor {
        return UIColor(red: 172.0/255.0, green: 221.0/255.0, blue: 173.0/255.0, alpha: 0.8)
    }
    static let pLBlue100 = UIColor(named: "PLBlue100")
    static let pLBlue10 = UIColor(named: "PLBlue10")
    static let pYellow = UIColor(named: "PYellow")
    
    static let sRed = UIColor(named: "SRed")
    
    static let gray50 = UIColor(named: "Gray50")
    static let gray30 = UIColor(named: "Gray30")
    static let gray10 = UIColor(named: "Gray10")
    
    static let black100 = UIColor(named: "Black100")
    static let black80 = UIColor(named: "Black80")
    
    convenience init(hex: String, alpha: CGFloat? = nil) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: alpha ?? CGFloat(a) / 255)
    }
}
