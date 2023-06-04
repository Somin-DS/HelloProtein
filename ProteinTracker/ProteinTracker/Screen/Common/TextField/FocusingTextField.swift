//
//  FocusTextField.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit
import SnapKit

class FocusingTextField: UIView {

    private var textField = UITextField()
    
    private var highLightView: UIView = {
       let view = UIView()
        view.backgroundColor = .clear
        view.setCornerRadius(cornerRadius: 16)
        view.layer.borderColor = UIColor.pLBlue10?.cgColor
        view.layer.borderWidth = 2
        return view
        
    }()
    
    private var keyboardType:UIKeyboardType = .numberPad {
        didSet {
            textField.keyboardType = keyboardType
        }
    }
    var isFocusing = false {
        didSet {
            highLightView.isHidden = isFocusing
            setNeedsLayout()
        }
    }

    init(type: UIKeyboardType) {
        super.init(frame: .zero)
        self.setGrayAndBorderView()
        configureKeyboard(type)
        setLayout()
        highLightView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureKeyboard(_ type: UIKeyboardType) {
        textField.textAlignment = .center
        textField.keyboardType = type
    }
    
    private func setLayout() {
        self.addSubview(textField)
        self.addSubview(highLightView)
        textField.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        highLightView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
