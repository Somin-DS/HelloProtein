//
//  Alert.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/04/08.
//

import UIKit


class Alert {
    func setOnlyMessageAlert(message: String) -> UIAlertController {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: LocalizeStrings.setting_alert.localized, style: .default)
        alert.addAction(okAction)
        return alert
    }
    
    func setAlert(title: String, message: String) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: LocalizeStrings.close_button.localized, style: .cancel)
        alert.addAction(cancelAction)
        return alert
    }
}
