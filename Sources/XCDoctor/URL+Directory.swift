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
        (try? resourceValues(forKeys: [.isDirectoryKey])
            .isDirectory  // file exists and is a directory
        ) ?? false  // file does not exist
    }
}
