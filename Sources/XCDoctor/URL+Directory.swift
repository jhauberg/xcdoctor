//
//  URL+Directory.swift
//  XCDoctor
//
//  Created by Jacob Hauberg Hansen on 14/07/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

extension URL {
    var isDirectory: Bool {
        let values = try? resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory ?? false
    }
}
