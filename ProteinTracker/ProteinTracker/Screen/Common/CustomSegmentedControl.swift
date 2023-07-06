//
//  CustomSegmentedControl.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/12.
//

import UIKit

class CustomSegmentedControl: UISegmentedControl {
    private let segmentInset: CGFloat = 5
    private let segmentColor: UIColor = .white
    private lazy var segmentImage: UIImage? = UIImage(color: segmentColor)

    override init(items: [Any]?) {
        super.init(items: items)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        commonInit()
    }
    
    private func commonInit() {
        backgroundColor = .tertiarySystemFill
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = bounds.height / 2
        
        let foregroundIndex = numberOfSegments
        
        if let foregroundImageView = subviews[foregroundIndex] as? UIImageView {
            foregroundImageView.bounds = foregroundImageView.bounds.inset(by: UIEdgeInsets(top: segmentInset, left: segmentInset, bottom: segmentInset, right: segmentInset))
            foregroundImageView.image = segmentImage
            foregroundImageView.layer.removeAnimation(forKey: "SelectionBounds")
            foregroundImageView.layer.masksToBounds = true
            foregroundImageView.layer.cornerRadius = foregroundImageView.bounds.height / 2

        }
    }
    
}

extension UIImage{
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
}
