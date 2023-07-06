//
//  FocusTextField.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit
import SnapKit

class FocusingTextField: BaseView {

    @IBOutlet weak var highlightView: UIView!
    @IBOutlet weak var textField: UITextField!
    
    private var keyboardType:UIKeyboardType = .numberPad {
        didSet {
            textField.keyboardType = keyboardType
        }
    }
    
    var isFocusing = false {
        didSet {
            highlightView.isHidden = !isFocusing
            setNeedsLayout()
        }
    }

    override func initView() {
        self.backgroundColor = .white
        self.setCornerRadius(cornerRadius: 10)
        setHighlightView()
    }
    
    private func setHighlightView() {
        highlightView.setCornerRadius(cornerRadius: 10)
        highlightView.layer.borderColor = UIColor.pLBlue10?.cgColor
        highlightView.layer.borderWidth = 2
        highlightView.backgroundColor = .clear
        highlightView.isHidden = true
    }
    
    func configureKeyboard(_ type: UIKeyboardType) {
        textField.textAlignment = .center
        textField.keyboardType = type
    }
    
    func setPlaceholder(_ text: String) {
        textField.placeholder = text
    }
    
}
