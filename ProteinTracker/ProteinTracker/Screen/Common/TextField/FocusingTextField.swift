//
//  FocusTextField.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit

class FocusingTextField: UIView {

    private var textField = UITextField()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setGrayAndBorderView()
        configureTextField()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setGrayAndBorderView()
    }
    
    private func configureTextField() {
    }
}
