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
    case nonExistentPaths
}

public struct Diagnosis {
    public let conclusion: String
    public let help: String?
    public let cases: [String]?
}

func nonExistentFilePaths(in project: XcodeProject) -> [String] {
    project.files.filter { ref -> Bool in
        // include this reference if file does not exist
        !FileManager.default.fileExists(atPath: ref.path)
    }.map { ref -> String in
        ref.path
    }
}

func nonExistentGroupPaths(in project: XcodeProject) -> [String] {
    project.groups.filter { ref -> Bool in
        !FileManager.default.fileExists(atPath: ref.path)
    }.map { ref -> String in
        "\(ref.path): Path referenced in group \"\(ref.name)\""
    }
}

func propertyListReferences(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref -> Bool in
        ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist"
    }
}

func danglingFilePaths(in project: XcodeProject) -> [String] {
    project.files.filter { ref -> Bool in
        !ref.isHeaderFile && ref.isSourceFile && !ref.hasTargetMembership
    }.filter { ref -> Bool in
        // handle the special-case Info.plist
        if ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist" {
            return !project.referencesPropertyListInfoPlist(named: ref)
        }
        return true
    }.map { ref -> String in
        ref.path
    }
}

func sourceFiles(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref -> Bool in
        ref.isSourceFile
    }
}

struct Resource {
    let name: String
    let fileName: String?

    var nameVariants: [String] {
        if let fileName = fileName {
            let plainFileName = fileName
                .replacingOccurrences(of: "@1x", with: "")
                .replacingOccurrences(of: "@2x", with: "")
                .replacingOccurrences(of: "@3x", with: "")
            let plainName = name
                .replacingOccurrences(of: "@1x", with: "")
                .replacingOccurrences(of: "@2x", with: "")
                .replacingOccurrences(of: "@3x", with: "")
            return Array(Set([
                name,
                plainName,
                fileName,
                plainFileName,
            ]))
        }
        return [name]
    }
}

func resources(in project: XcodeProject) -> [Resource] {
    let sources = sourceFiles(in: project)
    return project.files.filter { ref -> Bool in
        // TODO: specific exclusions? e.g. "archive.ar"/"a", ".whatever" etc
        ref.hasTargetMembership &&
            ref.url.pathExtension != "a" &&
            ref.url.pathExtension != "xcconfig" &&
            !ref.url.lastPathComponent.hasPrefix(".") &&
            !sources.contains { sourceRef -> Bool in
                ref.url == sourceRef.url
            }
    }.map { ref -> Resource in
        Resource(name: ref.url.deletingPathExtension().lastPathComponent,
                 fileName: ref.url.lastPathComponent)
    }
}

extension URL {
    var isAssetURL: Bool {
        FileManager.default.fileExists(atPath:
            appendingPathComponent("Contents.json").path)
    }
}

func assetURLs(at url: URL) throws -> [URL] {
    guard let dirEnumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey]
    ) else {
        return []
    }

    return try dirEnumerator.filter { item -> Bool in
        guard let fileUrl = item as? URL else {
            return false
        }
        let attr = try fileUrl.resourceValues(forKeys: [
            .isDirectoryKey,
        ])
        if !attr.isDirectory! {
            return false
        }
        if !fileUrl.isAssetURL {
            return false
        }
        guard !fileUrl.pathExtension.isEmpty else {
            // probably a folder; keep recursing
            return false
        }
        return true
    }.map { item -> URL in
        item as! URL
    }
}

func assets(in project: XcodeProject) throws -> [Resource] {
    try project.files.filter { ref -> Bool in
        ref.kind == "folder.assetcatalog" || ref.url.pathExtension == "xcassets"
    }.flatMap { ref -> [Resource] in
        try assetURLs(at: ref.url).map { assetUrl -> Resource in
            Resource(name: assetUrl.deletingPathExtension().lastPathComponent,
                     fileName: nil)
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
    case .nonExistentPaths:
        let dirPaths = nonExistentGroupPaths(in: project)
        if !dirPaths.isEmpty {
            return Diagnosis(
                conclusion: "non-existent path(s) referenced in groups",
                help: """
                If not corrected, these paths can cause tools to erroneously
                map children of each group to non-existent files.
                """,
                cases: dirPaths
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
                conclusion: "corrupt plist(s)",
                help: """
                These files must be fixed manually using any plain-text editor.
                """,
                cases: corruptedFilePaths
            )
        }
    case .danglingFiles:
        let filePaths = danglingFilePaths(in: project)
        if !filePaths.isEmpty {
            return Diagnosis(
                conclusion: "file(s) not included in any target",
                help: """
                These files might not be used; consider whether they should be removed.
                """,
                cases: filePaths
            )
        }
    case .unusedResources:
        // TODO: the resulting resources could potentially contain duplicates;
        //       for example, if project contains two files:
        //         "Icon10@2x.png" and "Icon10@3x.png"
        //       this will result (as expected) in two different resources,
        //       however, these could be squashed into one (with additional variants)
        let assetFiles: [Resource]
        do {
            assetFiles = try assets(in: project)
        } catch {
            fatalError("\(error)")
        }
        var res = resources(in: project) + assetFiles
        for source in sourceFiles(in: project) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source.path,
                                                 isDirectory: &isDirectory),
                !isDirectory.boolValue else {
                continue
            }
            let fileContents: String
            do {
                // TODO: this is a potentially heavy operation, as we read in entire
                //       file at once; consider alternatives (grep through Process?)
                fileContents = try String(contentsOf: source.url)
            } catch {
                #if DEBUG
                    print(error)
                #endif
                continue
            }
            res = res.filter { resource -> Bool in
                for resourceName in resource.nameVariants {
                    let searchStrings: [String]
                    if source.kind == "text.plist.xml" || source.url.pathExtension == "plist" {
                        // search without quotes in property-lists; typically text in node contents
                        // e.g. "<key>Icon10</key>"
                        searchStrings = ["\(resourceName)"]
                    } else {
                        // search with quotes in anything else; typically referenced as strings
                        // in sourcecode and string attributes in xml (xib/storyboard)
                        // e.g. `UIImage(named: "Icon10")`, or
                        //      `<imageView ... image="Icon10" ...>`
                        // however, consider the case:
                        //      `loadspr("res/monster.png")`
                        // here, the resource is actually "monster.png", but a build/copy phase
                        // has moved the resource to another destination; this means searching
                        //      `"monster.png"`
                        // won't work out as we want it to; instead, we can just try to match
                        // the end, which should work out no matter the destination, while
                        // still being decently specific; e.g.
                        //      `/monster.png"`
                        // TODO: this does not take commented lines into account
                        //       - we could expand to support // comments; e.g.
                        //         if resourceName occurs on a line preceded by "//"
                        //         anywhere previously, then it doesn't count
                        //         /**/ comments are much trickier, though
                        searchStrings = ["\"\(resourceName)\"", "/\(resourceName)\""]
                    }
                    for searchString in searchStrings {
                        if fileContents.contains(searchString) {
                            return false // resource seems to be used; don't search further for this
                        }
                    }
                }
                return true // resource seems to be unused; keep searching for usages
            }
        }
        // find special cases, e.g. AppIcon
        res = res.filter { resource -> Bool in
            for resourceName in resource.nameVariants {
                if project.referencesAssetAsAppIcon(named: resourceName) {
                    return false // resource seems to be used; don't search further for this
                }
            }
            return true // resource seems to be unused; keep searching for usages
        }
        if !res.isEmpty {
            return Diagnosis(
                conclusion: "unused resource(s)",
                help: """
                These resources might not be used; consider whether they should be removed.
                Note that this diagnosis is prone to produce false-positives as it can not
                realistically detect all usages with certainty.
                For example, assets specified through external references, or by dynamically
                constructed names, are likely to be reported as unused resources, even though
                they are actually used.
                """,
                cases: res.map { resource -> String in
                    // prefer name including extension, as this can help distinguish
                    // between asset catalog resources and plain resources not catalogued
                    resource.fileName ?? resource.name
                }
            )
        }
    }
    return nil
}
