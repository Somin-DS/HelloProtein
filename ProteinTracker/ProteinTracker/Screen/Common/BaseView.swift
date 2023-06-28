//
//  BaseView.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/28.
//

import UIKit

class BaseView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setView()
        initView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setView()
        initView()
    }
    
    private func setView() {
        guard let view = Bundle.main.loadNibNamed(
            String(describing: type(of: self)), owner: self, options: nil)?.first as? UIView else {
            return
        }
        view.frame = self.bounds
        self.addSubview(view)
    }
    
    func initView() {
        
    }
    
}
