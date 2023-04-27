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

    let progress = JGProgressHUD()
    let localRealm = try! Realm()
    lazy var searchHistoryRealm = localRealm.objects(SearchHistory.self)
    var resultArray = [Food]()
    var errorFlag = false
    var searchFlag = false
    var proteinName: String!
    var proteinIntake: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchBar.delegate = self
        tableView.dataSource = self
        tableView.delegate = self
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeButtonClicked))
        navigationItem.rightBarButtonItem?.tintColor = .black
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
    }
    
    func getProteinEn(_ keyword: String) {

        if let path = Bundle.main.path(forResource: "Protein-En", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
                let jsonObj = try JSON(data: data)
                for (_, subJson):(String, JSON) in jsonObj {
                    if subJson["Food"].stringValue.lowercased().contains(keyword.lowercased()) {
                        self.resultArray.append(Food(name: subJson["Food"].stringValue, proteinContent: subJson["Protein"].stringValue))
                    }
                }
                self.tableView.reloadData()
                progress.dismiss()
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
        //테스트
        let startDate = Date()
        
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else { return }
        guard let urlcomponents = URLComponents(string: "http://openapi.foodsafetykorea.go.kr/api/\(apiKey)/I2790/json/1/5/DESC_KOR=\(keyword)") else { return }
        
        guard let requestUrl = urlcomponents.url else { return }
        
        // URLRequest 생성
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print("Error: No data returned from API")
                return
            }
            
            do {
                let apiResponse = try JSONDecoder().decode(APIData.self, from: data)
                self.resultArray = apiResponse.I2790.row
                DispatchQueue.main.async {
                    self.progress.dismiss()
                    self.tableView.reloadData()
                    print("소요시간:\(Date().timeIntervalSince(startDate))")
                }
                
            } catch {
                print("Error decoding API response: \(error)")
            }
            
        }
        task.resume()
    }
}

extension SearchViewController: UISearchBarDelegate {
    
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
            cell.setText(text: row.proteinName)
            cell.deleteButton.tag = indexPath.row
            cell.deleteButton.addTarget(self, action: #selector(deleteButtonClicked(_:)), for: .touchUpInside)
            return cell
        }else {
            if !errorFlag && resultArray.count != 0 {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ResultSearchTableViewCell.identifier, for: indexPath) as? ResultSearchTableViewCell else {return UITableViewCell()}
                
                let row = resultArray[indexPath.row]
                cell.setText(name: row.name, protein: "\(row.proteinContent)g")
                return cell
        
            } else {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptyTableViewCell.identifier, for: indexPath) as? EmptyTableViewCell else {return UITableViewCell()}
                
                if errorFlag {
                    cell.setText(text: LocalizeStrings.search_error.localized)
                }else {
                    cell.setText(text: LocalizeStrings.search_empty.localized)
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
                NotificationCenter.default.post(name: .proteinName, object: nil, userInfo: ["name" : row.name])
                NotificationCenter.default.post(name: .proteinIntake, object: nil, userInfo: ["intake" : row.proteinContent])
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
    
}
