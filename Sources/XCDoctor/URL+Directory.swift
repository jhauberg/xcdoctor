//
//  URL+Directory.swift
//  XCDoctor
//
//  Created by Jacob Hauberg Hansen on 14/07/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

extension URL {
    /**
     A Boolean that is `true` if the URL points to a directory that exists.
     */
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey])
            .isDirectory  // file exists and is a directory
        ) ?? false  // file does not exist
    }

    /**
     A Boolean that is `true` if the URL points to a directory containing a "Contents.json" file.
     */
    var isAssetDirectory: Bool {
        FileManager.default.fileExists(
            atPath: appendingPathComponent("Contents.json").path
        )
    }
}
