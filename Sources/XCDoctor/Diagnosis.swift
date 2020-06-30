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
        // TODO: specific exclusions? e.g. "archive.ar"/"a"
        ref.hasTargetMembership && ref.url.pathExtension != "a" &&
            !sources.contains { sourceRef -> Bool in
                ref.url == sourceRef.url
            }
    }.map { ref -> Resource in
        Resource(name: ref.url.deletingPathExtension().lastPathComponent,
                 fileName: ref.url.lastPathComponent)
    }
}

func assets(in project: XcodeProject) -> [Resource] {
    project.files.filter { ref -> Bool in
        ref.kind == "folder.assetcatalog" || ref.url.pathExtension == "xcassets"
    }.flatMap { ref -> [Resource] in
        do {
            let assets = try FileManager.default.contentsOfDirectory(atPath: ref.url.path)
                .filter { file -> Bool in
                    FileManager.default.fileExists(atPath:
                        ref.url
                            .appendingPathComponent(file)
                            .appendingPathComponent("Contents.json").path)
                }
            return assets.map { asset -> Resource in
                Resource(name: String(asset[..<asset.lastIndex(of: ".")!]),
                         fileName: nil)
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
        var res = resources(in: project) + assets(in: project)
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
                    let searchString: String
                    if source.kind == "text.plist.xml" || source.url.pathExtension == "plist" {
                        // search without quotes in property-lists; typically text in node contents
                        // e.g. "<key>Icon10</key>"
                        searchString = "\(resourceName)"
                    } else {
                        // search with quotes in anything else; typically referenced as strings
                        // in sourcecode and string attributes in xml (xib/storyboard)
                        // e.g. "UIImage(named: "Icon")", or
                        //      "<imageView ... image="Icon10" ...>"
                        // TODO: this does not take commented lines into account
                        //       - we could expand to support // comments; e.g.
                        //         if resourceName occurs on a line preceded by "//"
                        //         anywhere previously, then it doesn't count
                        //         /**/ comments are much trickier, though
                        searchString = "\"\(resourceName)\""
                    }
                    if fileContents.contains(searchString) {
                        return false // resource seems to be used; don't search further for this
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
                realistically detect all usages.
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
