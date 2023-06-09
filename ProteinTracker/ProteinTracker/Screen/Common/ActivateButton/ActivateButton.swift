//
//  ActivateButton.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit

enum ActivateButtonType {
    case start
    case update
    case add
}

class ActivateButton: UIButton {
    
    var isActive: Bool = false {
        didSet {
            self.isEnabled = isActive
            isActive ? (self.backgroundColor = .pLBlue100) : (self.backgroundColor = .gray50)
            self.setNeedsLayout()
        }
    }
    
    init() {
        super.init(frame: .zero)
        configureButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureButton()
    }
    
    private func configureButton() {
        self.setCornerRadius(cornerRadius: 24)
        self.backgroundColor = .gray50
        self.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        self.isEnabled = false
    }
    
    
    func setButton(_ type: ActivateButtonType) {
           var title: String
           switch type {
           case .start:
               title = "Start"
           case .update:
               title = "Update"
           case .add:
               title = "Add"
           }
        
        //TODO - font extension
        self.setButtonColorText(text: title, font: UIFont(name: "SFProRounded-Semibold", size: 20) ?? UIFont(), textColor: .white)
       }
    
}

protocol ActivateButtonDelegate {
    func buttonClicked()
}
