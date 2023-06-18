//
//  BaseViewModel.swift
//  ProteinTracker
//
//  Created by Somin Park on 2023/06/18.
//

import Foundation

class BaseViewModel {
    var reloadView: ((Any?) -> ())?
}

protocol BaseViewModelDelegate {
    func getData()
    func fetchData(_ data: Any?)
}
