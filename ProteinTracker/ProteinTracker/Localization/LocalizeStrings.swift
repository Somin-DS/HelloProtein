//
//  LocalizeStrings.swift
//  ProteinTracker
//
//  Created by 박소민 on 2021/11/24.
//

import Foundation

enum LocalizeStrings: String {
    case setting_language,
         setting_intake,
         setting_theme,
         add_namelabel,
         add_intakelabel,
         add_favoritelabel,
         add_button,
         close_button,
         stats_averagelabel,
         stats_segone,
         stats_segtwo,
         init_weightfield,
         init_activelabel,
         init_segone,
         init_segtwo,
         init_segthree,
         init_callabel,
         init_recommendlabel,
         init_targetfield,
         init_startbutton,
         empty_weight,
         empty_protein,
         error_number
    
    var localized: String {
        return self.rawValue.localized()
    }
}
