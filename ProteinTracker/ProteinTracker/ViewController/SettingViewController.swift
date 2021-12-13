//
//  SettingViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/23.
//

import UIKit
import MessageUI

class SettingViewController: UIViewController, MFMailComposeViewControllerDelegate {


    var settings: [[String]] = []
    var info: [String] = []
    @IBOutlet weak var settingTableView: UITableView!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        settingTableView.delegate = self
        settingTableView.dataSource = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        title = "Setting"
        info = [ LocalizeStrings.setting_qna.localized, LocalizeStrings.setting_info.localized]
        
    }
    override func viewWillAppear(_ animated: Bool) {
        settings = [[LocalizeStrings.setting_intake.localized, "\(UserDefaults.standard.string(forKey: "targetProtein")!)g"], [LocalizeStrings.setting_language.localized, UserDefaults.standard.string(forKey: "searchLanguage")!]]
        settingTableView.reloadData()
    }
    
    func sendEmail() {
        if MFMailComposeViewController.canSendMail() {
                    
            let compseVC = MFMailComposeViewController()
            compseVC.mailComposeDelegate = self
            
            compseVC.setToRecipients(["ramgoods2@gmail.com"])
            compseVC.setSubject("[Hello, Protein!] QnA")
            compseVC.setMessageBody("Content", isHTML: false)
            
            self.present(compseVC, animated: true, completion: nil)
            
        }
        else {
            self.showSendMailErrorAlert()
        }
                
    }
    
    func showSendMailErrorAlert() {
        let sendMailErrorAlert = UIAlertController(title: LocalizeStrings.setting_mailAlertTitle.localized, message:LocalizeStrings.setting_mailAlertMessage.localized, preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: LocalizeStrings.setting_alert.localized, style: .default) {
                    (action) in
                    print(LocalizeStrings.setting_alert.localized)
                }
                sendMailErrorAlert.addAction(confirmAction)
                self.present(sendMailErrorAlert, animated: true, completion: nil)
            
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
           controller.dismiss(animated: true, completion: nil)
       }
}

extension SettingViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return LocalizeStrings.setting_sectionOne.localized
        }else {
            return LocalizeStrings.setting_sectionTwo.localized
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return settings.count
        }else {
            return info.count
        }
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = settingTableView.dequeueReusableCell(withIdentifier: SettingTableViewCell.identifier, for: indexPath) as? SettingTableViewCell else { return UITableViewCell()}
        
        cell.titleLabel.textAlignment = .center
        cell.titleLabel.numberOfLines = 0
        cell.titleLabel.font = UIFont().bodyFont
        cell.detailLabel.textAlignment = .center
        cell.detailLabel.numberOfLines = 0
        cell.detailLabel.font = UIFont().bodyFont
        
        if indexPath.section == 0 {
            let row = settings[indexPath.row]
            cell.titleLabel.text = row[0]
            cell.detailLabel.text = row[1]
            
        }else {
            let row = info[indexPath.row]
            cell.titleLabel.text = row
            cell.detailLabel.text = ""
        }
        
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "SettingTargetViewController") as! SettingTargetViewController
                self.navigationController?.pushViewController(vc, animated: true)
            }else if indexPath.row == 1{
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "SettingLanguageViewController") as! SettingLanguageViewController
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }else {
            if indexPath.row == 0 {
                sendEmail()
            }else {
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "InfoOpenSourceViewController") as! InfoOpenSourceViewController
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
        
        
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
}
