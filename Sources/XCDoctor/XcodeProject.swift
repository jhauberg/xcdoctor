//
//  XcodeProject.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

// a mapping of `lastKnownFileType` and its common extensions
let sourceTypes: [(String, [String])] = [
    ("file.storyboard", ["storyboard"]),
    ("file.xib", ["xib", "nib"]),
    ("folder.assetcatalog", ["xcassets"]),
    ("sourcecode.c.c", ["c"]),
    ("sourcecode.c.objc", ["m"]),
    ("sourcecode.cpp.objcpp", ["mm"]),
    ("sourcecode.cpp.cpp", ["cpp", "cc"]),
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
}

public struct XcodeProject {
    let pbxUrl: URL
    let rootUrl: URL

    var files: [FileReference] {
        refs
    }

    private var refs: [FileReference] = []

    private let propertyList: [String: Any]

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
                    if let parentPath = obj["path"] as? String,
                        !parentPath.isEmpty {
                        path = "\(parentPath)/\(path)"
                    } else {
                        // non-folder group or root of hierarchy
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
