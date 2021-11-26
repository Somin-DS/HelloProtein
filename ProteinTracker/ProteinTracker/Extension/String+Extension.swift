//
//  String+Extension.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/24.
//

import Foundation

extension String {
    
    //localization
    func localized() ->String {
        return NSLocalizedString(self, comment: "")
    }
}
