//
//  UIView+Extension.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/04/08.
//

import UIKit

extension UIView {
    
    func setCornerRadius(cornerRadius: CGFloat) {
        self.layer.masksToBounds = true
        self.layer.cornerRadius = cornerRadius
    }
    
    func setCommonLayout(cornerRadius: CGFloat, borderWidth: CGFloat) {
        self.backgroundColor = .white
        self.layer.masksToBounds = true
        self.layer.cornerRadius = cornerRadius
        self.layer.borderColor = UIColor().mainGreen.cgColor
        self.layer.borderWidth = borderWidth
    }
    
    func setGrayAndBorderView() {
        self.layer.masksToBounds = true
        self.layer.cornerRadius = 10
        self.backgroundColor = .gray10
        self.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
    }
    
}

extension UITextField {
    func setText(placeholder: String, font: UIFont, textAlignment: NSTextAlignment) {
        self.placeholder = placeholder
        self.font = font
        self.textAlignment = textAlignment
    }
}

extension UILabel {
    func setText(text: String, font: UIFont) {
        self.text = text
        self.font = font
        self.numberOfLines = 0
    }
    
    func setCommonLable(font: UIFont) {
        self.textAlignment = .center
        self.numberOfLines = 0
        self.font = font
        self.lineBreakMode = .byWordWrapping
    }
}

extension UIButton {
    func setButtonColorText(text: String, font: UIFont, textColor: UIColor) {
        self.setTitle(text, for: .normal)
        self.titleLabel?.font = font
        self.setTitleColor(textColor, for: .normal)
    }
}
