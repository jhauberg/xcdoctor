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
    let url: URL?
    let projectUrl: URL // TODO: naming, this is the visual tree as seen in Xcode
    let name: String
    let hasChildren: Bool

    var path: String? {
        url?.standardized.relativePath
    }
}

struct FileReference {
    let url: URL
    // TODO: could add visual/project url here as well to help locating a non-existent file in project
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

public enum XcodeProjectError: Error, Equatable {
    case incompatible(reason: String)
    case notFound(amongFilesInDirectory: Bool) // param indicates whether directory was searched
}

public struct XcodeProject {
    public static func open(from url: URL) -> Result<XcodeProject, XcodeProjectError> {
        let projectUrl: URL

        if !FileManager.default.fileExists(atPath: url.standardized.path) {
            return .failure(.notFound(amongFilesInDirectory: url.hasDirectoryPath))
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
                return .failure(.notFound(amongFilesInDirectory: true))
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

    private func resolveProjectURL(ref: Dictionary<String, Any>.Element,
                                   groups: [String: Any]) -> URL? {
        guard let obj = ref.value as? [String: Any] else {
            return nil
        }
        guard var path = obj["name"] as? String ?? obj["path"] as? String else {
            return nil
        }

        var parentReferences = parents(of: ref.key, in: groups)
        while !parentReferences.isEmpty {
            assert(parentReferences.count == 1)
            let p = parentReferences.first!
            let groupObj = p.value as! [String: Any]
            if let parentPath = groupObj["name"] as? String ?? groupObj["path"] as? String,
                !parentPath.isEmpty {
                path = "\(parentPath)/\(path)"
            }
            parentReferences = parents(of: p.key, in: groups)
        }

        return URL(string: path)
    }

    private func resolveFileURL(ref: Dictionary<String, Any>.Element,
                                groups: [String: Any]) -> URL? {
        guard let obj = ref.value as? [String: Any] else {
            return nil
        }
        guard let sourceTree = obj["sourceTree"] as? String,
            var path = obj["path"] as? String else {
            return nil
        }
        switch sourceTree {
        case "":
            // skip this file
            return nil
        case "SDKROOT":
            // skip this file
            return nil
        case "DEVELOPER_DIR":
            // skip this file
            return nil
        case "BUILT_PRODUCTS_DIR":
            // skip this file
            return nil
        case "SOURCE_ROOT":
            // leave path unchanged
            break
        case "<absolute>":
            // leave path unchanged
            break
        case "<group>":
            var parentReferences = parents(of: ref.key, in: groups)
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
                parentReferences = parents(of: p.key, in: groups)
            }
        default:
            fatalError()
        }
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path)
        }
        return rootUrl.appendingPathComponent(path)
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
                    isa == "PBXGroup" || isa == "PBXVariantGroup" {
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
            guard let fileUrl = resolveFileURL(ref: file, groups: groupReferences) else {
                continue
            }
            let obj = file.value as! [String: Any]
            let potentialFileType = obj["lastKnownFileType"] as? String
            let explicitfileType = obj["explicitFileType"] as? String
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
        for group in groupReferences {
            let obj = group.value as! [String: Any]
            guard let children = obj["children"] as? [String] else {
                continue
            }
            guard let projectUrl = resolveProjectURL(ref: group, groups: groupReferences) else {
                continue
            }
            let name = obj["name"] as? String ?? obj["path"] as? String ?? "<unknown>"
            let directoryUrl = resolveFileURL(ref: group, groups: groupReferences)
            groupRefs.append(
                GroupReference(
                    url: directoryUrl,
                    projectUrl: projectUrl,
                    name: name,
                    hasChildren: !children.isEmpty
                )
            )
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

    func referencesPropertyListAsInfoPlist(named file: FileReference) -> Bool {
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
