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

final class DailyTargetViewController: UIViewController {

    @IBOutlet weak var weightTextField: FocusingTextField!
    @IBOutlet weak var weightLabel: UILabel!
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

    }
    override func viewWillAppear(_ animated: Bool) {
        configureButton()
        weightTextField.configureKeyboard(.numberPad)
        targetProteinTextField.configureKeyboard(.numberPad)
    }
    init?(type: DailyTargetType, corder: NSCoder) {
        super.init(coder: corder)
        self.type = type
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
