//
//  Item.swift
//  RollingFilm
//
//  Created by 啊傻傻傻 on 2026/3/10.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
