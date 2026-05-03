//
//  Item.swift
//  VideoCompressor
//
//  Created by Rishaal on 2026-05-03.
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
