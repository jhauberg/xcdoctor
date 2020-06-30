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
    ("sourcecode.c.h", ["h"]),
    ("sourcecode.c.objc", ["m"]),
    ("sourcecode.cpp.objcpp", ["mm"]),
    ("sourcecode.cpp.cpp", ["cpp", "cc"]),
    ("sourcecode.cpp.h", ["h", "hh"]),
    ("sourcecode.swift", ["swift"]),
    ("sourcecode.metal", ["metal", "mtl"]),
]

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
        url.pathExtension == "h" || url.pathExtension == "hh"
    }
}

public struct XcodeProject {
    let pbxUrl: URL
    let rootUrl: URL

    var files: [FileReference] {
        refs
    }

    func referencesAssetAsAppIcon(named asset: String) -> Bool {
        for elem in buildConfigs {
            if let config = elem.value as? [String: Any] {
                if let settings = config["buildSettings"] as? [String: Any] {
                    if let appIconSetting = settings["ASSETCATALOG_COMPILER_APPICON_NAME"] as? String {
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
                            of: "$(SRCROOT)", with: rootUrl.standardized.path)
                        if file.url.standardized.path.hasSuffix(setting) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private var refs: [FileReference] = []

    private let propertyList: [String: Any]
    private var buildConfigs: [String: Any] = [:]

    public init?(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: .mutableContainersAndLeaves,
                format: &format
            )
            propertyList = plist as! [String: Any]
            pbxUrl = url
            rootUrl = pbxUrl // for example,    ~/Development/My/Project.xcodeproj/project.pbxproj
                .deletingLastPathComponent() // ~/Development/My/Project.xcodeproj/
                .deletingLastPathComponent() // ~/Development/My/
            resolve()
        } catch {
            return nil
        }
    }

    private mutating func resolve() {
        refs.removeAll()

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
                    let obj = p.value as! [String: Any]
                    if obj["name"] == nil {
                        if let parentPath = obj["path"] as? String,
                            !parentPath.isEmpty {
                            path = "\(parentPath)/\(path)"
                        } else {
                            // non-folder group or root of hierarchy
                        }
                    } else {
                        // edge case, group might also have path, but it is likely invalid
                    }
                    parentReferences = parents(of: p.key, in: groupReferences)
                }
            default:
                fatalError()
            }
            let fileUrl: URL
            if NSString(string: path).isAbsolutePath {
                fileUrl = URL(fileURLWithPath: path)
            } else {
                fileUrl = rootUrl.appendingPathComponent(path)
            }
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
            refs.append(
                FileReference(
                    url: fileUrl,
                    kind: explicitfileType ?? potentialFileType ?? "unknown",
                    hasTargetMembership: isReferencedAsBuildFile
                ))
        }
    }

    private func parents(of reference: String, in groups: [String: Any])
        -> [String: Any] {
        groups.filter { group -> Bool in
            let groupObj = group.value as! [String: Any]
            let children = groupObj["children"] as! [String]
            return children.contains(reference)
        }
    }
}
