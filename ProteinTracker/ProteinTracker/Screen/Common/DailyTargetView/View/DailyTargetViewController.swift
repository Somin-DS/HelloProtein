//
//  DailyTargetViewController.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/04.
//

import UIKit

enum DailyTargetType {
    case onboarding, setting
}

final class DailyTargetViewController: BaseViewController<DailyTargetViewModel> {

    @IBOutlet weak var weightLabel: UILabel!
    @IBOutlet weak var weightTextField: FocusingTextField!
    @IBOutlet weak var weightSegementControl: UISegmentedControl!
    @IBOutlet weak var activeLabel: UILabel!
    @IBOutlet weak var activeTableView: UITableView!
    @IBOutlet weak var optionalLabel: UILabel!
    @IBOutlet weak var optionalTableView: UITableView!
    @IBOutlet weak var targetProteinLabel: UILabel!
    @IBOutlet weak var targetProteinTextField: FocusingTextField!
    @IBOutlet weak var targetDescLabel: UILabel!
    private var activeButton = ActivateButton()

    private var type: DailyTargetType = .onboarding
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initViewModel(DailyTargetViewModel())
        configureButton()
        setupUI()
        activeTableView.delegate = self
        activeTableView.dataSource = self
        optionalTableView.delegate = self
        optionalTableView.dataSource = self
        weightTextField.textField.delegate = self
        targetProteinTextField.textField.delegate = self
    }
    
    init?(type: DailyTargetType, corder: NSCoder) {
        super.init(coder: corder)
        self.type = type
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupUI() {
        view.backgroundColor = .secondarySystemBackground
        weightLabel.setTitleText(viewModel?.weightTitle, color: .secondaryLabel, size: 17, weight: .semibold)
        weightTextField.configureKeyboard(.numberPad)
        weightTextField.setPlaceholder("0")
        
        activeLabel.setTitleText(viewModel?.activeTitle, color: .secondaryLabel, size: 17, weight: .semibold)
        activeTableView.setCornerRadius(cornerRadius: 10)
        activeTableView.backgroundColor = .white
        
        optionalLabel.setTitleText(viewModel?.optionalTitle, color: .secondaryLabel, size: 17, weight: .semibold)
        optionalTableView.setCornerRadius(cornerRadius: 10)
        optionalTableView.backgroundColor = .white
        
        targetProteinLabel.setTitleText(viewModel?.targetProteinTitle, color: .secondaryLabel, size: 20)
        targetProteinTextField.configureKeyboard(.numberPad)
        targetProteinTextField.setPlaceholder("0")
        
        targetDescLabel.setTitleText(viewModel?.targetDescTitle, color: .tertiaryLabel, size: 16)
        
        activeButton.tintColor = .secondaryLabel
    }
    
    private func configureButton() {
        self.view.addSubview(activeButton)
        activeButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(36)
        }
        switch type {
        case .onboarding:
            activeButton.setButton(.start)
        case .setting:
            activeButton.setButton(.update)
        }
    }
}

extension DailyTargetViewController: UITextFieldDelegate, UIGestureRecognizerDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == weightTextField.textField {
            weightTextField.isFocusing = true
        } else {
            targetProteinTextField.isFocusing = true
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == weightTextField.textField {
            weightTextField.isFocusing = false
        } else {
            targetProteinTextField.isFocusing = false
        }
    }
}
