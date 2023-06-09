//
//  FocusTextField.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit
import SnapKit

class FocusingTextField: UIView {

    @IBOutlet weak var highlightView: UIView!
    @IBOutlet weak var textField: UITextField!
    
    private var keyboardType:UIKeyboardType = .numberPad {
        didSet {
            textField.keyboardType = keyboardType
        }
    }
    
    var isFocusing = false {
        didSet {
            highlightView.isHidden = isFocusing
            setNeedsLayout()
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        setView()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setView()
    }
    
    private func setView() {
        guard let view = Bundle.main.loadNibNamed(
            String(describing: type(of: self)), owner: self, options: nil)?.first as? UIView else {
            return
        }
        view.frame = self.bounds
        self.addSubview(view)
        self.backgroundColor = .clear
        self.setCornerRadius(cornerRadius: 10)
        self.layer.borderColor = UIColor.pLBlue10?.cgColor
        self.layer.borderWidth = 2
        self.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
    }
    
    func configureKeyboard(_ type: UIKeyboardType) {
        textField.textAlignment = .center
        textField.keyboardType = type
    }
    
}
