//
//  UIFont+Extension.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/12/01.
//
/*
        ====> TmoneyRoundWind-Regular
        ====> TmoneyRoundWind-ExtraBold
                Binggrae-Bold
        */

import UIKit

extension UIFont {
    var headFont: UIFont {
        return UIFont(name: "Binggrae-Bold", size: 22)!
    }
    var bodyFont: UIFont {
        return UIFont(name: "Binggrae-Bold", size: 16)!
    }
    var subFont: UIFont {
        return UIFont(name: "Binggrae-Bold", size: 19)!
    }
    var strFont:UIFont {
        return UIFont(name: "TmoneyRoundWind-Regular", size: 12)!
    }
    
    var labelFont: UIFont {
        return UIFont(name: "Binggrae-Bold", size: 14)!
    }
    
    class func rounded(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let font: UIFont
        
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        } else {
            font = systemFont
        }
        return font
    }
}
