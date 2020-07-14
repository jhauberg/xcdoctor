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

// represents any object in a pbxproj file; it's essentially just a key (id) and a dict
private struct PBXObject {
    let id: String
    let properties: [String: Any]
}

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
    let kind: String?
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

struct ProductReference {
    let name: String
    let buildsSourceFiles: Bool
}

public enum XcodeProjectError: Error, Equatable {
    case incompatible(reason: String)
    case notFound(amongFilesInDirectory: Bool) // param indicates whether directory was searched
}

private struct XcodeProjectLocation {
    let root: URL // directory containing .xcodeproj
    let xcodeproj: URL // path to .xcodeproj
    let pbx: URL // path to .xcodeproj/project.pbxproj
    var name: String { // MyProject.xcodeproj
        xcodeproj.lastPathComponent
    }
}

private func findProjectLocation(from url: URL) -> Result<XcodeProjectLocation, XcodeProjectError> {
    let xcodeprojUrl: URL
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
            xcodeprojUrl = url.appendingPathComponent(xcodeProjectFile)
        } else {
            return .failure(.notFound(amongFilesInDirectory: true))
        }
    } else {
        xcodeprojUrl = url
    }
    let pbxUrl = xcodeprojUrl.appendingPathComponent("project.pbxproj")
    if !FileManager.default.fileExists(atPath: pbxUrl.standardized.path) {
        return .failure(.incompatible(reason: "unsupported Xcode project format"))
    }
    let directoryUrl = xcodeprojUrl // for example, ~/Development/My/Project.xcodeproj
        .deletingLastPathComponent() //             ~/Development/My/
    return .success(XcodeProjectLocation(
        root: directoryUrl,
        xcodeproj: xcodeprojUrl,
        pbx: pbxUrl
    ))
}

private func parent(of object: PBXObject, in groups: [PBXObject]) -> PBXObject? {
    groups.filter { parent -> Bool in
        if let children = parent.properties["children"] as? [String] {
            return children.contains(object.id)
        }
        return false
    }.first
}

private func resolveProjectURL(object: PBXObject, groups: [PBXObject]) -> URL? {
    guard var path = object.properties["name"] as? String ?? object
        .properties["path"] as? String else {
        return nil
    }

    var ref = object
    while let parent = parent(of: ref, in: groups) {
        if let parentPath = parent.properties["name"] as? String ?? parent
            .properties["path"] as? String,
            !parentPath.isEmpty {
            path = "\(parentPath)/\(path)"
        }
        ref = parent
    }

    return URL(string: path)
}

private func resolveFileURL(
    object: PBXObject,
    groups: [PBXObject],
    fromProjectLocation location: XcodeProjectLocation
) -> URL? {
    guard let sourceTree = object.properties["sourceTree"] as? String,
        var path = object.properties["path"] as? String else {
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
            if let parentPath = parent.properties["path"] as? String, !parentPath.isEmpty {
                path = "\(parentPath)/\(path)"
                let groupSourceTree = parent.properties["sourceTree"] as! String
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
    return location.root.appendingPathComponent(path)
}

private func objectReferences(in objectGraph: [String: Any]) -> [PBXObject] {
    guard let objects = objectGraph["objects"] as? [String: Any] else {
        return []
    }

    return objects.map { (key: String, value: Any) -> PBXObject in
        PBXObject(id: key, properties: value as? [String: Any] ?? [:])
    }
}

private func objectsIdentifying(as identities: [String],
                                among objects: [PBXObject]) -> [PBXObject] {
    objects.filter { object -> Bool in
        if let identity = object.properties["isa"] as? String {
            return identities.contains(identity)
        }
        return false
    }
}

private func fileReferences(
    among objects: [PBXObject],
    fromProjectLocation location: XcodeProjectLocation
) -> [FileReference] {
    var fileRefs: [FileReference] = []
    let groupObjects = objectsIdentifying(as: ["PBXGroup", "PBXVariantGroup"], among: objects)
    let buildFileReferences = objectsIdentifying(as: ["PBXBuildFile"], among: objects)
        .map { object -> String in
            object.properties["fileRef"] as! String
        }

    let excludedFileTypes = ["wrapper.xcdatamodel"]

    for file in objectsIdentifying(as: ["PBXFileReference"], among: objects) {
        let potentialFileType = file.properties["lastKnownFileType"] as? String
        let explicitfileType = file.properties["explicitFileType"] as? String
        let fileType = explicitfileType ?? potentialFileType

        if let fileType = fileType, excludedFileTypes.contains(fileType) {
            continue
        }

        guard let fileUrl = resolveFileURL(
            object: file,
            groups: groupObjects,
            fromProjectLocation: location
        ) else {
            continue
        }

        var isReferencedAsBuildFile: Bool = false
        if buildFileReferences.contains(file.id) {
            // file is directly referenced as a build file
            isReferencedAsBuildFile = true
        } else {
            // file might be contained in a parent group that is referenced as a build file
            var ref = file
            while let parent = parent(of: ref, in: groupObjects) {
                if buildFileReferences.contains(parent.id) {
                    isReferencedAsBuildFile = true
                    break
                }
                ref = parent
            }
        }
        fileRefs.append(
            FileReference(
                url: fileUrl,
                kind: fileType,
                hasTargetMembership: isReferencedAsBuildFile
            )
        )
    }
    return fileRefs
}

private func groupReferences(
    among objects: [PBXObject],
    fromProjectLocation location: XcodeProjectLocation
) -> [GroupReference] {
    var groupRefs: [GroupReference] = []
    let groupObjects = objectsIdentifying(as: ["PBXGroup", "PBXVariantGroup"], among: objects)
    for group in groupObjects {
        guard let children = group.properties["children"] as? [String],
            let projectUrl = resolveProjectURL(object: group, groups: groupObjects) else {
            continue
        }
        guard let name = group.properties["name"] as? String ??
            group.properties["path"] as? String else {
            continue
        }
        let directoryUrl = resolveFileURL(
            object: group,
            groups: groupObjects,
            fromProjectLocation: location
        )
        groupRefs.append(
            GroupReference(
                url: directoryUrl,
                projectUrl: projectUrl,
                name: name,
                hasChildren: !children.isEmpty
            )
        )
    }
    return groupRefs
}

private func productReferences(among objects: [PBXObject]) -> [ProductReference] {
    var productRefs: [ProductReference] = []
    for target in objectsIdentifying(as: ["PBXNativeTarget"], among: objects) {
        guard let name = target.properties["name"] as? String else {
            continue
        }
        var compilesAnySource =
            false // false until we determine any compilation phase of at least one source file
        if let phases = target.properties["buildPhases"] as? [String] {
            let compilationPhases = objects.filter { object -> Bool in
                phases.contains(object.id)
            }.filter { phase -> Bool in
                if let isa = phase.properties["isa"] as? String {
                    return isa == "PBXSourcesBuildPhase"
                }
                return false
            }
            if !compilationPhases.isEmpty {
                for phase in compilationPhases {
                    if let sources = phase.properties["files"] as? [String], !sources.isEmpty {
                        // target compiles at least one source file
                        compilesAnySource = true
                        break
                    }
                }
            }
        }
        productRefs.append(
            ProductReference(
                name: name,
                buildsSourceFiles: compilesAnySource
            )
        )
    }
    return productRefs
}

public struct XcodeProject {
    /**
     Attempts to locate and evaluate an Xcode project at a given URL.

     If the URL leads to a directory, files in that directory will be enumerated in search
     of an .xcodeproj (subdirectories will not be searched).
     */
    public static func openAndEvaluate(
        from url: URL,
        beforeOpeningProject: ((String) -> Void)? = nil,
        beforeEvaluatingProject: ((String) -> Void)? = nil
    )
        -> Result<XcodeProject, XcodeProjectError> {
        let projectLocation: XcodeProjectLocation
        switch findProjectLocation(from: url) {
        case let .success(location):
            projectLocation = location
        case let .failure(error):
            return .failure(error)
        }
        beforeOpeningProject?(projectLocation.name)
        do {
            var format = PropertyListSerialization.PropertyListFormat.openStep
            guard let plist = try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: projectLocation.pbx),
                options: .mutableContainersAndLeaves,
                format: &format
            ) as? [String: Any] else {
                return .failure(.incompatible(reason: "unsupported Xcode project format"))
            }
            beforeEvaluatingProject?(projectLocation.name)
            return .success(
                XcodeProject(locatedAt: projectLocation, objectGraph: plist)
            )
        } catch {
            return .failure(.incompatible(reason: "unsupported Xcode project format"))
        }
    }

    private init(locatedAt location: XcodeProjectLocation, objectGraph: [String: Any]) {
        self.location = location

        let objects = objectReferences(in: objectGraph)

        buildConfigurations = objectsIdentifying(as: ["XCBuildConfiguration"], among: objects)
        files = fileReferences(among: objects, fromProjectLocation: location)
        groups = groupReferences(among: objects, fromProjectLocation: location)
        products = productReferences(among: objects)
    }

    private let location: XcodeProjectLocation
    private let buildConfigurations: [PBXObject]

    let files: [FileReference]
    let groups: [GroupReference]
    let products: [ProductReference]

    func referencesAssetAsAppIcon(named asset: String) -> Bool {
        for object in buildConfigurations {
            if let settings = object.properties["buildSettings"] as? [String: Any] {
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
        for object in buildConfigurations {
            if let settings = object.properties["buildSettings"] as? [String: Any] {
                if let infoPlistSetting = settings["INFOPLIST_FILE"] as? String {
                    let setting = infoPlistSetting.replacingOccurrences(
                        of: "$(SRCROOT)", with: location.root.standardized.path
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
