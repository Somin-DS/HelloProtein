//
//  SearchViewController.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/25.
//

import UIKit
import RealmSwift
import Alamofire
import SwiftyJSON
import JGProgressHUD

class SearchViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!
    // 언제 show, hide
    let progress = JGProgressHUD()
    let localRealm = try! Realm()
    var searchHistoryRealm: Results<SearchHistory>!
    var resultArray = [[String]]()
    var errorFlag = false
    var searchFlag = false
    var proteinName: String!
    var proteinIntake: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        searchBar.showsCancelButton = true
        searchBar.delegate = self
        tableView.dataSource = self
        tableView.delegate = self
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeButtonClicked))
        navigationItem.rightBarButtonItem?.tintColor = .black
        
        searchHistoryRealm = localRealm.objects(SearchHistory.self)
    }
                                                            
    @objc func closeButtonClicked() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func addTapGesture(_ sender: UITapGestureRecognizer) {
        
        view.endEditing(true)
    }
    
    func searchProtein ( _ keyword: String) {
        errorFlag = false
        searchFlag = true
        resultArray = []
        progress.show(in: tableView, animated: true)
        let language = UserDefaults.standard.string(forKey: "searchLanguage")
        if language == "English(영어)" {
            getProteinEn(keyword)
        } else {
            getProteinKo(keyword)
        }
        progress.dismiss()
    }
    
    func getProteinEn(_ keyword: String) {

        if let path = Bundle.main.path(forResource: "Protein-En", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
                let jsonObj = try JSON(data: data)
                for (_, subJson):(String, JSON) in jsonObj {
                    if subJson["Food"].stringValue.lowercased().contains(keyword.lowercased()) {
                        self.resultArray.append([subJson["Food"].stringValue, subJson["Protein"].stringValue])
                    }
                }
                self.tableView.reloadData()
            } catch {
                errorFlag = true
                self.tableView.reloadData()
            }
        } else {
            errorFlag = true
            self.tableView.reloadData()
        }
    }
    
    func getProteinKo(_ keyword: String) {
        let param: Parameters = [
            "desc_kor" : keyword
                 ]

        let urlstring = "http://apis.data.go.kr/1470000/FoodNtrIrdntInfoService/getFoodNtrItdntList?ServiceKey=aeIT3Znjq3tXJhg0t8faoxSUHmdddOlWbO%2FM6rFqukYe%2BUBH272yyI%2Frg51RlTY6M9YfG0zjML%2FHCLmNFYSpNw%3D%3D&type=json"

        let url = URL(string: urlstring)!

        AF.request(url, method: .get, parameters: param).responseJSON() { response in
          switch response.result {
          case .success(let value):
              let json = JSON(value)
              let items = json["body"]["items"]
              for i in items {
                  let protein = i.1["NUTR_CONT3"].stringValue
                  let food = i.1["DESC_KOR"].stringValue

                  if self.resultArray.isEmpty {
                    self.resultArray.append([food, protein])
                  }else {
                      var flag = false
                      for i in self.resultArray {
                          if i[0] == food {
                              flag = true
                          }
                      }
                      if !flag {
                          self.resultArray.append([food, protein])
                      }
                  }
              }
              self.tableView.reloadData()
              
          case .failure:
              self.errorFlag = true
              self.tableView.reloadData()
            return
          }
        }
    }
    
}

extension SearchViewController: UISearchBarDelegate {
    
    //검색버튼 눌렀을때
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        if let text = searchBar.text {
            searchProtein(text)
            let history = SearchHistory(proteinName: text)
            if searchHistoryRealm.filter("proteinName == '\(text)'").count == 0 {
                try! localRealm.write {
                localRealm.add(history)
                }
            }
        }
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
        tableView.reloadData()
    }
    
    //서치바에 커서 깜빡이기 시작할때
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        searchFlag = false
        tableView.reloadData()
    }
}

extension SearchViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !searchFlag {
            return searchHistoryRealm.count
        }else {
            return resultArray.count == 0 ? 1 : resultArray.count
        }
    }
    
    @objc func deleteButtonClicked(_ sender: UIButton) {

        try! localRealm.write {
            localRealm.delete(searchHistoryRealm[sender.tag])
        }
        tableView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if !searchFlag {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: RecentSearchTableViewCell.identifier, for: indexPath) as? RecentSearchTableViewCell else {return UITableViewCell()}
            let row = searchHistoryRealm[indexPath.row]
            cell.recentLabel.text = row.proteinName
            cell.deleteButton.tag = indexPath.row
            
            cell.deleteButton.addTarget(self, action: #selector(deleteButtonClicked(_:)), for: .touchUpInside)
            
            return cell
        }else {
            if !errorFlag && resultArray.count != 0 {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ResultSearchTableViewCell.identifier, for: indexPath) as? ResultSearchTableViewCell else {return UITableViewCell()}
                
                let row = resultArray[indexPath.row]
                
                cell.nameLabel.text = row[0]
                cell.proteinLabel.text = "\(row[1])g"
                cell.nameLabel.numberOfLines = 0
                cell.nameLabel.lineBreakMode = .byWordWrapping
                cell.proteinLabel.numberOfLines = 0
                cell.proteinLabel.lineBreakMode = .byWordWrapping
                
                return cell
        
            } else {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptyTableViewCell.identifier, for: indexPath) as? EmptyTableViewCell else {return UITableViewCell()}
                
                if errorFlag {
                    cell.titleLabel.text = LocalizeStrings.search_error.localized
                }else {
                    cell.titleLabel.text = LocalizeStrings.search_empty.localized
                }
                return cell
            }
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !searchFlag {
            return LocalizeStrings.search_historyTitle.localized
        }else {
            return LocalizeStrings.search_resultTitle.localized
        }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !searchFlag {
            let row = searchHistoryRealm[indexPath.row]
            searchProtein(row.proteinName)
        }else {
            if !errorFlag && !resultArray.isEmpty {
                let row = resultArray[indexPath.row]
                NotificationCenter.default.post(name: .proteinName, object: nil, userInfo: ["name" : row[0]])
                NotificationCenter.default.post(name: .proteinIntake, object: nil, userInfo: ["intake" : row[1]])
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
    
}
