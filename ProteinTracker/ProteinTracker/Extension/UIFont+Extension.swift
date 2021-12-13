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

import Foundation
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
}
