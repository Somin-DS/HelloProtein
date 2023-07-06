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
        
        viewModel?.reloadTableView = { type in
            if type == .activityLevel {
                self.activeTableView.reloadData()
            } else {
                self.optionalTableView.reloadData()
            }
        }
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

extension DailyTargetViewController: UITableViewDelegate, UITableViewDataSource {
//    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        if tableView == activeTableView {
//            activeTableView.cellForRow(at: indexPath as IndexPath)?.accessoryType = .checkmark
//            viewModel?.selectCell(type: .activityLevel, at: indexPath)
//        } else {
//            optionalTableView.cellForRow(at: indexPath as IndexPath)?.accessoryType = .checkmark
//            viewModel?.selectCell(type: .optiontional, at: indexPath)
//        }
//    }
//
//    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
//        if tableView == activeTableView {
//            activeTableView.cellForRow(at: indexPath as IndexPath)?.accessoryType = .none
//            viewModel?.selectCell(type: .activityLevel, at: indexPath)
//        } else {
//            optionalTableView.cellForRow(at: indexPath as IndexPath)?.accessoryType = .none
//            viewModel?.selectCell(type: .optiontional, at: indexPath)
//        }
//    }
//
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == activeTableView {
            return viewModel?.numberOfActivityLevel ?? 0
        } else {
            return viewModel?.numberOfOptional ?? 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { return UITableViewCell() }
        if tableView == activeTableView {
            guard let cell = activeTableView.dequeueReusableCell(withIdentifier: ActivityLevelTableViewCell.identifier, for: indexPath) as? ActivityLevelTableViewCell else { return UITableViewCell()}
            cell.configureCell(viewModel: viewModel.getCellViewModel(type: .activityLevel, at: indexPath))
            return cell
        } else {
            guard let cell = optionalTableView.dequeueReusableCell(withIdentifier: OptionalTableViewCell.identifier, for: indexPath) as? OptionalTableViewCell else { return UITableViewCell()}
            cell.configureCell(viewModel: viewModel.getCellViewModel(type: .optiontional, at: indexPath))
            return cell
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
