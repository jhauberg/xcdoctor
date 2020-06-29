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
    case unusedResources
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
        ref.path
    }
}

func propertyListReferences(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref -> Bool in
        ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist"
    }
}

func danglingFilePaths(in project: XcodeProject) -> [String] {
    project.files.filter { ref -> Bool in
        ref.isSourceFile && !ref.hasTargetMembership
    }.map { ref -> String in
        ref.path
    }
}

func sourceFiles(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref -> Bool in
        ref.isSourceFile
    }
}

func assetNames(in project: XcodeProject) -> [String] {
    project.files.filter { ref -> Bool in
        ref.kind == "folder.assetcatalog" || ref.url.pathExtension == "xcassets"
    }.flatMap { ref -> [String] in
        do {
            let assets = try FileManager.default.contentsOfDirectory(atPath: ref.url.path)
                .filter { file -> Bool in
                    return FileManager.default.fileExists(atPath:
                        ref.url
                            .appendingPathComponent(file)
                            .appendingPathComponent("Contents.json").path)
            }
            return assets.map { asset -> String in
                String(asset[..<asset.lastIndex(of: ".")!])
            }
        } catch {
            return []
        }
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
            } catch let error as NSError {
                let additionalInfo: String
                if let helpfulErrorMessage = error.userInfo[NSDebugDescriptionErrorKey] as? String {
                    // this is typically along the lines of:
                    //  "Value missing for key inside <dict> at line 7"
                    additionalInfo = helpfulErrorMessage
                } else {
                    // this is typically more like:
                    //  "The data couldn’t be read because it isn’t in the correct format."
                    additionalInfo = error.localizedDescription
                }
                corruptedFilePaths.append("\(file.path): \(additionalInfo)")
            }
        }
        if !corruptedFilePaths.isEmpty {
            return Diagnosis(
                conclusion: "corrupt plist",
                help: "fix these by editing as plain-text using any editor",
                cases: corruptedFilePaths
            )
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
    case .unusedResources:
        var assets = assetNames(in: project)
        // TODO: basically, grep -r "\"asset_name_here\"", but only for files in project
        for source in sourceFiles(in: project) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source.url.path,
                                                 isDirectory: &isDirectory),
                !isDirectory.boolValue else {
                continue
            }
            let fileContents: String
            do {
                fileContents = try String(contentsOf: source.url)
            } catch {
                #if DEBUG
                    print(error)
                #endif
                continue
            }
            assets = assets.filter({ assetName -> Bool in
                !fileContents.contains("\"\(assetName)\"")
            })
        }
        if !assets.isEmpty {
            return Diagnosis(
                conclusion: "unused resources",
                help: """
                These assets might not be in use; consider whether they should be removed.
                Keep in mind that this diagnosis is prone to produce false-positives as it
                can not realistically detect all uses. For example, assets specified through
                dynamically constructed resource names are likely to be reported as
                unused resources.
                """,
                cases: assets
            )
        }
    }
    return nil
}
