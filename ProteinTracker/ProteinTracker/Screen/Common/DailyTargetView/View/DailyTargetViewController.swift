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
        weightLabel.setTitleText(viewModel?.weightTitle)
        weightTextField.configureKeyboard(.numberPad)
        weightSegementControl.setTitle(viewModel?.weightSegmentTitle[0], forSegmentAt: 0)
        weightSegementControl.setTitle(viewModel?.weightSegmentTitle[1], forSegmentAt: 1)
        
        activeLabel.setTitleText(viewModel?.activeTitle)
        activeTableView.setCornerRadius(cornerRadius: 10)
        activeTableView.backgroundColor = .white
        
        optionalLabel.setTitleText(viewModel?.optionalTitle)
        optionalTableView.setCornerRadius(cornerRadius: 10)
        optionalTableView.backgroundColor = .white
        
        targetProteinLabel.setTitleText(viewModel?.targetProteinTitle)
        targetProteinTextField.configureKeyboard(.numberPad)
        
        targetDescLabel.text = viewModel?.targetDescTitle
        targetDescLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        targetDescLabel.textColor = .tertiaryLabel
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
