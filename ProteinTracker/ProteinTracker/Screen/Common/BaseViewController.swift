//
//  BaseViewController.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/18.
//

import UIKit

class BaseViewController<T: BaseViewModel>: UIViewController {

    private var viewModel: T?
    
    var keyboardDelegate: KeyboardDelegate? {
        didSet {
            addKeyboardObserver()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setConstraints()
        configureView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if let keyboardDelegate {
            addKeyboardObserver()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if let keyboardDelegate {
            removeKeyboardObserver()
        }
    }

    private func initViewModel(_ viewModel: T?) {
        self.viewModel = viewModel
    }
    
    func setConstraints() {
        
    }
    
    func configureView() {
        
    }
    
    //TODO: 에러처리
    func showErrorMessage(_ error: Error) {
        
    }

    func addKeyboardObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    func removeKeyboardObserver() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc func keyboardWillShow(_ sender: Notification) {
        if let keyboardSize = (sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            keyboardDelegate?.keyboardWillShow(keyboardSize.height)
        }
    }
    
    @objc func keyboardWillHide(_ sender: Notification) {
        keyboardDelegate?.keyboardWillHide()
    }
}

protocol KeyboardDelegate {
    func keyboardWillHide()
    func keyboardWillShow(_ height: CGFloat)
}
