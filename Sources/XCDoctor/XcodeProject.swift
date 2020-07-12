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
    private var buildConfigs: [(String, [String: Any])] = []

    var files: [FileReference] {
        fileRefs
    }

    var groups: [GroupReference] {
        groupRefs
    }

    private func resolveProjectURL(object: (String, [String: Any]),
                                   groups: [(String, [String: Any])]) -> URL? {
        guard var path = object.1["name"] as? String ?? object.1["path"] as? String else {
            return nil
        }

        var ref = object
        while let parent = parent(of: ref, in: groups) {
            if let parentPath = parent.1["name"] as? String ?? parent.1["path"] as? String,
                !parentPath.isEmpty {
                path = "\(parentPath)/\(path)"
            }
            ref = parent
        }

        return URL(string: path)
    }

    private func resolveFileURL(object: (String, [String: Any]),
                                groups: [(String, [String: Any])]) -> URL? {
        guard let sourceTree = object.1["sourceTree"] as? String,
            var path = object.1["path"] as? String else {
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
            var ref = object
            while let parent = parent(of: ref, in: groups) {
                if let parentPath = parent.1["path"] as? String, !parentPath.isEmpty {
                    path = "\(parentPath)/\(path)"
                    let groupSourceTree = parent.1["sourceTree"] as! String
                    if groupSourceTree == "SOURCE_ROOT" {
                        // don't resolve further back, even if
                        // this group is a child of another group
                        break
                    }
                } else {
                    // non-folder group or root of hierarchy
                }
                ref = parent
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
        buildConfigs.removeAll()

        let items = objects()

        let fileItems = items.filter { _, props -> Bool in
            if let isa = props["isa"] as? String,
                isa == "PBXFileReference" {
                return true
            }
            return false
        }
        let groupItems = items.filter { _, props -> Bool in
            if let isa = props["isa"] as? String,
                isa == "PBXGroup" || isa == "PBXVariantGroup" {
                return true
            }
            return false
        }
        let buildFileReferences = items.filter { _, props -> Bool in
            if let isa = props["isa"] as? String,
                isa == "PBXBuildFile" {
                return true
            }
            return false
        }.map { _, props -> String in
            props["fileRef"] as! String
        }
        buildConfigs = items.filter { _, props -> Bool in
            if let isa = props["isa"] as? String,
                isa == "XCBuildConfiguration" {
                return true
            }
            return false
        }
        for file in fileItems {
            guard let fileUrl = resolveFileURL(object: file, groups: groupItems) else {
                continue
            }
            let potentialFileType = file.1["lastKnownFileType"] as? String
            let explicitfileType = file.1["explicitFileType"] as? String
            var isReferencedAsBuildFile: Bool = false
            if buildFileReferences.contains(file.0) {
                // file is directly referenced as a build file
                isReferencedAsBuildFile = true
            } else {
                // file might be contained in a parent group that is referenced as a build file
                var ref = file
                while let parent = parent(of: ref, in: groupItems) {
                    if buildFileReferences.contains(parent.0) {
                        isReferencedAsBuildFile = true
                        break
                    }
                    ref = parent
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
        for group in groupItems {
            guard let children = group.1["children"] as? [String] else {
                continue
            }
            guard let projectUrl = resolveProjectURL(object: group, groups: groupItems) else {
                continue
            }
            let name = group.1["name"] as? String ?? group.1["path"] as? String ?? "<unknown>"
            let directoryUrl = resolveFileURL(object: group, groups: groupItems)
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

    private func objects() -> [(String, [String: Any])] {
        if let objects = propertyList["objects"] as? [String: Any] {
            return objects.map { (key: String, value: Any) -> (String, [String: Any]) in
                (key, value as? [String: Any] ?? [:])
            }
        }
        return []
    }

    private func parent(of object: (String, [String: Any]), in groups: [(String, [String: Any])])
        -> (String, [String: Any])? {
        groups.filter { _, props -> Bool in
            if let children = props["children"] as? [String] {
                return children
                    .contains(object
                        .0) // TODO: better map to struct, stuff like this becomes unruly
            }
            return false
        }.first
    }

    func referencesAssetAsAppIcon(named asset: String) -> Bool {
        for (_, config) in buildConfigs {
            if let settings = config["buildSettings"] as? [String: Any] {
                if let appIconSetting =
                    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] as? String {
                    if appIconSetting == asset {
                        return true
                    }
                }
            }
        }
        return false
    }

    func referencesPropertyListAsInfoPlist(named file: FileReference) -> Bool {
        for (_, config) in buildConfigs {
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
        return false
    }
}
