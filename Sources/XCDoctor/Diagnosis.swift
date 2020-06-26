//
//  Diagnose.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

public enum Defect {
    case nonExistentFiles
}

public struct Diagnosis {
    public let conclusion: String
    public let help: String?
    public let cases: [String]?
}

public func examine(project: XcodeProject, for defects: [Defect]) -> [Diagnosis] {
    var diagnoses: [Diagnosis] = []
    // TODO: separate each examination into smaller parts; a func per defect?
    for defect in defects {
        switch defect {
        case .nonExistentFiles:
            let nonExistentFileUrls = project.fileUrls.filter { url -> Bool in
                !FileManager.default.fileExists(atPath: url.path)
            }
            if !nonExistentFileUrls.isEmpty {
                let paths = nonExistentFileUrls.map { (url) -> String in
                    url.standardized.relativePath
                }
                diagnoses.append(Diagnosis(
                    conclusion: "non-existent files are referenced in project",
                    help: "File references to non-existent files should be removed from the project.",
                    cases: paths
                ))
            }
        }
    }
    return diagnoses
}
