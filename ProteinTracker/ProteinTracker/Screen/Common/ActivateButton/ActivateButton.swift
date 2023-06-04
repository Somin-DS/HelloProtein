//
//  ActivateButton.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit

enum ButtonTypes {
    case start
    case update
    case add
}

class ActivateButton: UIButton {

    var isActive: Bool = false {
        didSet {
            self.isEnabled = isActive
            if isActive {
                self.backgroundColor = .pLBlue100
            }else {
                self.backgroundColor = .gray50
            }
            setNeedsLayout()
        }
    }
    
    init(type: ButtonTypes) {
        super.init(frame: .zero)
        self.backgroundColor = .gray50
        self.setCornerRadius(cornerRadius: 24)
        setButton(type)
    }
    
    private func setButton(_ type: ButtonTypes) {
        var title: String
        switch type {
        case .start:
            title = "Start"
        case .update:
            title = "Update"
        case .add:
            title = "Add"
        }
        self.setText(text: title, font: UIFont(name: "SFProRounded-Semibold", size: 20) ?? UIFont(), textColor: .white)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

protocol ActivateButtonDelegate {
    func buttonClicked()
}
