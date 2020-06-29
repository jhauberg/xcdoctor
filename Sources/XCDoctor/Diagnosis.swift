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
    case corruptPropertyLists
    case danglingFiles
}

public struct Diagnosis {
    public let conclusion: String
    public let help: String?
    public let cases: [String]?
}

func nonExistentFilePaths(in project: XcodeProject) -> [String] {
    project.files.filter { ref -> Bool in
        // include this reference if file does not exist
        !FileManager.default.fileExists(atPath: ref.url.path)
    }.map { ref -> String in
        return ref.path
    }
}

func propertyListReferences(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref -> Bool in
        ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist"
    }
}

func danglingFilePaths(in project: XcodeProject) -> [String] {
    project.files.filter { ref -> Bool in
        !ref.hasTargetMembership
    }.map { ref -> String in
        return ref.path
    }
}

public func examine(project: XcodeProject, for defect: Defect) -> Diagnosis? {
    switch defect {
    case .nonExistentFiles:
        let filePaths = nonExistentFilePaths(in: project)
        if !filePaths.isEmpty {
            return Diagnosis(
                conclusion: "non-existent file(s) referenced in project",
                // TODO: this text should be wrapped at X columns; can do manually, but ...
                help: """
                These files might have been moved or removed from the filesystem.
                In either case, each reference should be removed from the project;
                if a file has been moved, add back the file from its new location.
                """,
                cases: filePaths
            )
        }
    case .corruptPropertyLists:
        let files = propertyListReferences(in: project)
        var corruptedFilePaths: [String] = []
        for file in files {
            do {
                _ = try PropertyListSerialization.propertyList(
                    from: try Data(contentsOf: file.url),
                    format: nil
                )
            } catch {
                corruptedFilePaths.append(
                    file.path)
            }
        }
        if !corruptedFilePaths.isEmpty {
            return Diagnosis(
                conclusion: "corrupt plist",
                help: "fix these by editing as plain-text using any editor",
                cases: corruptedFilePaths)
        }
    case .danglingFiles:
        let filePaths = danglingFilePaths(in: project)
        if !filePaths.isEmpty {
            return Diagnosis(
                conclusion: "file(s) not included in any target",
                help: """
                These files might no longer be used; consider whether they should be deleted
                """,
                cases: filePaths
            )
        }
    }
    return nil
}
