//
//  Item.swift
//  Unstuck
//
//  Created by MacBook on 30.05.2026.
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
