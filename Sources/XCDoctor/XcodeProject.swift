//
//  XcodeProject.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

// a mapping of `lastKnownFileType` and its common extensions
// note that files matching these indicators will be subject
// to full-text search (unusedResources), so including assets
// (e.g. images, or videos, in particular) would not be ideal
let sourceTypes: [(String, [String])] = [
    ("file.storyboard", ["storyboard"]),
    ("file.xib", ["xib", "nib"]),
    ("folder.assetcatalog", ["xcassets"]),
    ("text.plist.strings", ["strings"]),
    ("text.plist.xml", ["plist"]),
    ("sourcecode.c.c", ["c"]),
    ("sourcecode.c.h", ["h", "pch"]),
    ("sourcecode.c.objc", ["m"]),
    ("sourcecode.cpp.objcpp", ["mm"]),
    ("sourcecode.cpp.cpp", ["cpp", "cc"]),
    ("sourcecode.cpp.h", ["h", "hh"]),
    ("sourcecode.swift", ["swift"]),
    ("sourcecode.metal", ["metal", "mtl"]),
    ("text.script.sh", ["sh"]),
]

struct GroupReference {
    let url: URL
    let name: String

    var path: String {
        url.standardized.relativePath
    }
}

struct FileReference {
    let url: URL
    let kind: String
    let hasTargetMembership: Bool

    var path: String {
        url.standardized.relativePath
    }

    var isSourceFile: Bool {
        sourceTypes.contains { (fileType, extensions) -> Bool in
            kind == fileType || extensions.contains(url.pathExtension)
        }
    }

    var isHeaderFile: Bool {
        // TODO: should have some way of checking against sourceTypes instead of repeating
        //       for example, a file like prefix.pch would not be considered a headerfile
        //       - but does have kind "sourcecode.c.h"
        url.pathExtension == "h" || url.pathExtension == "hh" || url.pathExtension == "pch"
    }
}

public enum XcodeProjectError: Error {
    case incompatible(reason: String)
    case notFound(among: [String]? = nil)
}

public struct XcodeProject {
    public static func open(from url: URL) -> Result<XcodeProject, XcodeProjectError> {
        let projectUrl: URL

        if !FileManager.default.fileExists(atPath: url.standardized.path) {
            return .failure(.notFound())
        }

        if !url.isDirectory {
            return .failure(.incompatible(reason: "not an Xcode project"))
        }

        if url.pathExtension != "xcodeproj" {
            let files = try! FileManager.default.contentsOfDirectory(
                atPath: url.standardized.path
            )
            if let xcodeProjectFile = files.first(where: { file -> Bool in
                file.hasSuffix("xcodeproj")
            }) {
                projectUrl = url.appendingPathComponent(xcodeProjectFile)
            } else {
                return .failure(.notFound(among: files))
            }
        } else {
            projectUrl = url
        }

        let pbxUrl = projectUrl.appendingPathComponent("project.pbxproj")

        if !FileManager.default.fileExists(atPath: pbxUrl.standardized.path) {
            return .failure(.incompatible(reason: "unsupported Xcode project format"))
        }

        do {
            var format = PropertyListSerialization.PropertyListFormat.openStep
            guard let plist = try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: pbxUrl),
                options: .mutableContainersAndLeaves,
                format: &format
            ) as? [String: Any] else {
                return .failure(.incompatible(reason: "unsupported Xcode project format"))
            }
            let rootUrl = pbxUrl // for example, ~/Development/My/Project.xcodeproj/project.pbxproj
                .deletingLastPathComponent() //  ~/Development/My/Project.xcodeproj/
                .deletingLastPathComponent() //  ~/Development/My/
            return .success(XcodeProject(locatedAtRootURL: rootUrl, objectGraph: plist))
        } catch {
            return .failure(.incompatible(reason: "unsupported Xcode project format"))
        }
    }

    private init(locatedAtRootURL url: URL, objectGraph: [String: Any]) {
        rootUrl = url
        propertyList = objectGraph
        resolve()
    }

    let rootUrl: URL

    private var fileRefs: [FileReference] = []
    private var groupRefs: [GroupReference] = []

    private let propertyList: [String: Any]
    private var buildConfigs: [String: Any] = [:]

    var files: [FileReference] {
        fileRefs
    }

    var groups: [GroupReference] {
        groupRefs
    }

    private mutating func resolve() {
        fileRefs.removeAll()
        groupRefs.removeAll()

        guard let objects = propertyList["objects"] as? [String: Any] else {
            return
        }

        let fileReferences = objects.filter { (elem) -> Bool in
            if let obj = elem.value as? [String: Any] {
                if let isa = obj["isa"] as? String,
                    isa == "PBXFileReference" {
                    return true
                }
            }
            return false
        }
        let groupReferences = objects.filter { (elem) -> Bool in
            if let obj = elem.value as? [String: Any] {
                if let isa = obj["isa"] as? String,
                    isa == "PBXGroup" || isa == "PBXVariantGroup",
                    let children = obj["children"] as? [String],
                    !children.isEmpty {
                    return true
                }
            }
            return false
        }
        let buildReferences = objects.filter { (elem) -> Bool in
            if let obj = elem.value as? [String: Any] {
                if let isa = obj["isa"] as? String,
                    isa == "PBXBuildFile" {
                    return true
                }
            }
            return false
        }.map { (elem) -> String in
            let obj = elem.value as! [String: Any]
            return obj["fileRef"] as! String
        }
        buildConfigs = objects.filter { (elem) -> Bool in
            if let obj = elem.value as? [String: Any] {
                if let isa = obj["isa"] as? String,
                    isa == "XCBuildConfiguration" {
                    return true
                }
            }
            return false
        }
        for file in fileReferences {
            let obj = file.value as! [String: Any]
            var path = obj["path"] as! String
            let sourceTree = obj["sourceTree"] as! String
            let potentialFileType = obj["lastKnownFileType"] as? String
            let explicitfileType = obj["explicitFileType"] as? String
            switch sourceTree {
            case "":
                // skip this file
                continue
            case "SDKROOT":
                // skip this file
                continue
            case "DEVELOPER_DIR":
                // skip this file
                continue
            case "BUILT_PRODUCTS_DIR":
                // skip this file
                continue
            case "SOURCE_ROOT":
                // leave path unchanged
                break
            case "<absolute>":
                // leave path unchanged
                break
            case "<group>":
                var parentReferences = parents(of: file.key, in: groupReferences)
                while !parentReferences.isEmpty {
                    assert(parentReferences.count == 1)
                    let p = parentReferences.first!
                    let groupObj = p.value as! [String: Any]
                    if let parentPath = groupObj["path"] as? String, !parentPath.isEmpty {
                        path = "\(parentPath)/\(path)"
                        let groupSourceTree = groupObj["sourceTree"] as! String
                        if groupSourceTree == "SOURCE_ROOT" {
                            // don't resolve further back, even if
                            // this group is a child of another group
                            break
                        }
                    } else {
                        // non-folder group or root of hierarchy
                    }
                    parentReferences = parents(of: p.key, in: groupReferences)
                }
            default:
                fatalError()
            }
            let fileUrl = resolvePath(path)
            var isReferencedAsBuildFile: Bool = false
            if buildReferences.contains(file.key) {
                // file is directly referenced as a build file
                isReferencedAsBuildFile = true
            } else {
                // file might be contained in a parent group that is referenced as a build file
                var parentReferences = parents(of: file.key, in: groupReferences)
                while !parentReferences.isEmpty {
                    assert(parentReferences.count == 1)
                    let p = parentReferences.first!
                    if buildReferences.contains(p.key) {
                        isReferencedAsBuildFile = true
                        break
                    }
                    parentReferences = parents(of: p.key, in: groupReferences)
                }
            }
            fileRefs.append(
                FileReference(
                    url: fileUrl,
                    kind: explicitfileType ?? potentialFileType ?? "unknown",
                    hasTargetMembership: isReferencedAsBuildFile
                )
            )
        }

        // TODO: this is almost completely duplicated from file traversal, though with
        //       a difference of path being optional
        for group in groupReferences {
            let obj = group.value as! [String: Any]
            guard var path = obj["path"] as? String else {
                continue
            }
            let sourceTree = obj["sourceTree"] as! String
            switch sourceTree {
            case "":
                // skip this file
                continue
            case "SDKROOT":
                // skip this file
                continue
            case "DEVELOPER_DIR":
                // skip this file
                continue
            case "BUILT_PRODUCTS_DIR":
                // skip this file
                continue
            case "SOURCE_ROOT":
                // leave path unchanged
                break
            case "<absolute>":
                // leave path unchanged
                break
            case "<group>":
                var parentReferences = parents(of: group.key, in: groupReferences)
                while !parentReferences.isEmpty {
                    assert(parentReferences.count == 1)
                    let p = parentReferences.first!
                    let groupObj = p.value as! [String: Any]
                    if let parentPath = groupObj["path"] as? String, !parentPath.isEmpty {
                        path = "\(parentPath)/\(path)"
                        let groupSourceTree = groupObj["sourceTree"] as! String
                        if groupSourceTree == "SOURCE_ROOT" {
                            // don't resolve further back, even if
                            // this group is a child of another group
                            break
                        }
                    } else {
                        // non-folder group or root of hierarchy
                    }
                    parentReferences = parents(of: p.key, in: groupReferences)
                }
            default:
                fatalError()
            }
            let directoryUrl = resolvePath(path)
            let name: String
            if let named = obj["name"] as? String {
                name = named
            } else {
                // grab path as-is, unresolved
                name = obj["path"] as! String
            }
            groupRefs.append(
                GroupReference(
                    url: directoryUrl,
                    name: name
                )
            )
        }
    }

    private func resolvePath(_ path: String) -> URL {
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path)
        }
        return rootUrl.appendingPathComponent(path)
    }

    private func parents(of reference: String, in groups: [String: Any])
        -> [String: Any] {
        groups.filter { group -> Bool in
            let groupObj = group.value as! [String: Any]
            let children = groupObj["children"] as! [String]
            return children.contains(reference)
        }
    }

    func referencesAssetAsAppIcon(named asset: String) -> Bool {
        for elem in buildConfigs {
            if let config = elem.value as? [String: Any] {
                if let settings = config["buildSettings"] as? [String: Any] {
                    if let appIconSetting =
                        settings["ASSETCATALOG_COMPILER_APPICON_NAME"] as? String {
                        if appIconSetting == asset {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    func referencesPropertyListInfoPlist(named file: FileReference) -> Bool {
        for elem in buildConfigs {
            if let config = elem.value as? [String: Any] {
                if let settings = config["buildSettings"] as? [String: Any] {
                    if let infoPlistSetting = settings["INFOPLIST_FILE"] as? String {
                        let setting = infoPlistSetting.replacingOccurrences(
                            of: "$(SRCROOT)", with: rootUrl.standardized.path
                        )
                        if file.url.standardized.path.hasSuffix(setting) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
}
