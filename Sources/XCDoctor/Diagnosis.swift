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

func nonExistentFilePaths(in project: XcodeProject) -> [String] {
    project.fileUrls.filter { url -> Bool in
        // include this url if file does not exist
        !FileManager.default.fileExists(atPath: url.path)
    }.map { url -> String in
        // transform url to readable path
        url.standardized.relativePath
    }
}

public func examine(project: XcodeProject, for defects: [Defect]) -> [Diagnosis] {
    var diagnoses: [Diagnosis] = []
    // TODO: separate each examination into smaller parts; a func per defect?
    for defect in defects {
        switch defect {
        case .nonExistentFiles:
            let files = nonExistentFilePaths(in: project)
            if !files.isEmpty {
                diagnoses.append(Diagnosis(
                    conclusion: "non-existent file(s) referenced in project",
                    // TODO: this text should be wrapped at X columns; can do manually, but ...
                    help: """
                    These files might have been moved or removed from the filesystem.
                    In either case, each reference should be removed from the project;
                    if a file has been moved, add back the file from its new location.
                    """,
                    cases: files
                ))
            }
        }
    }
    return diagnoses
}
