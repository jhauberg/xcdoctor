//
//  Diagnosis.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

/**
 Represents an undesired condition for an Xcode project.
 */
public enum Defect {
    /**
     A condition that applies if any file reference resolves to a file that does not exist on disk.
     */
    case nonExistentFiles
    /**
     A condition that applies if any property-list (".plist") fails to convert to a
     serialized representation.
     */
    case corruptPropertyLists
    /**
     A condition that applies if any source-file does not have target membership.
     */
    case danglingFiles
    /**
     A condition that applies if any non-source-file (including resources in assetcatalogs)
     does not appear to be used in any source-file.

     Whether or not a resource is deemed to be in use relies on simple full-text pattern matching
     and is prone to both false-positives and false-negatives.

     Some cases require more context to resolve, and is beyond the scope of this examination.

     For example, a case where a string represents both a piece of text, but _also_ a resource,
     will deem the resource to be in use just by the existence of the text string. To properly
     resolve this, one would need to know more context; is this string used as a piece of text,
     or is it a reference to something else?

     Similarly, a case where a resource reference is assembled at run-time could trigger a
     false-positive that this resource is not used because it does not literally appear verbatim.
     */
    case unusedResources(strippingSourceComments: Bool)
    /**
     A condition that applies if any asset set does not contain any files or resources
     other than asset catalog information (i.e. "Contents.json").

     For `.colorset` assets, the condition applies if the catalog information does not contain
     any color components.
     */
    case emptyAssets
    /**
     A condition that applies if any groups (including non-folder groups) resolves to
     a path that does not exist on disk.
     */
    case nonExistentPaths
    /**
     A condition that applies if any group contains zero children (files or groups).
     */
    case emptyGroups
    /**
     A condition that applies if any native target is not built from at least one source-file.
     */
    case emptyTargets
}

/**
 Represents a diagnosis of a defect in an Xcode project.
 */
public struct Diagnosis {
    /**
     Represents a conclusive message for the result of this diagnosis.
     */
    public let conclusion: String
    /**
     Represents a helpful message on how to go about dealing with this diagnosis.
     */
    public let help: String?
    /**
     Represents a set of concrete cases that are directly linked to causing this diagnosis.
     */
    public let cases: [String]?
}

private func nonExistentFiles(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref in
        // include this reference if file does not exist
        !FileManager.default.fileExists(atPath: ref.path)
    }
}

private func nonExistentGroups(
    in project: XcodeProject
) -> [GroupReference] {
    project.groups.filter { ref in
        if let path = ref.path {
            return !FileManager.default.fileExists(atPath: path)
        }
        return false
    }
}

private func emptyGroups(in project: XcodeProject) -> [GroupReference] {
    project.groups.filter { ref in
        !ref.hasChildren
    }
}

private func emptyTargets(in project: XcodeProject) -> [ProductReference] {
    project.products.filter { ref in
        !ref.buildsSourceFiles
    }
}

private func propertyListReferences(in project: XcodeProject) -> [FileReference] {
    project.files.filter { ref in
        ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist"
    }
}

private func danglingFiles(
    in project: XcodeProject
) -> [FileReference] {
    project.files
        .filter { ref in
            !ref.isHeaderFile && ref.isSourceFile && !ref.hasTargetMembership
        }
        .filter { ref in
            if ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist" {
                return !project.referencesPropertyListAsInfoPlist(named: ref)
            }
            return true
        }
}

private func sourceFiles(in project: XcodeProject) -> [FileReference] {
    let exceptFiles = nonExistentFiles(in: project)
    return project.files.filter { ref in
        ref.isSourceFile  // file is compiled in one way or another
            && !ref.url.isDirectory  // file is text-based; i.e. not a directory
            && !exceptFiles.contains(where: { otherRef -> Bool in  // file exists
                ref.url == otherRef.url
            })
    }
}

extension String {
    fileprivate var removingScaleFactors: String {
        replacingOccurrences(of: "@1x", with: "")
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@3x", with: "")
    }
}

private func fontFamilyVariants(from url: URL) -> [String] {
    guard let data = NSData(contentsOf: url),
        let provider = CGDataProvider(data: data),
        let font = CGFont(provider)
    else {
        return []
    }
    var variants: [String] = []
    if let fullName = font.fullName {
        variants.append(String(fullName))
    }
    if let postScriptName = font.postScriptName {
        variants.append(String(postScriptName))
    }
    return variants
}

private struct Resource: Equatable {
    let url: URL
    let name: String
    let fileName: String
    let nameVariants: [String]

    var path: String {
        url.standardized.relativePath
    }

    init(at url: URL) {
        self.url = url

        name = url.deletingPathExtension().lastPathComponent
        fileName = url.lastPathComponent

        var names: [String] = [
            name,
            name.removingScaleFactors,
            fileName,
            fileName.removingScaleFactors,
        ]

        if url.pathExtension == "ttf" || url.pathExtension == "otf" {
            names.append(
                contentsOf: fontFamilyVariants(from: url)
            )
        }

        nameVariants = Array(
            Set(names)  // remove any potential duplicates
        )
    }
}

private func resourceFiles(in project: XcodeProject) -> [Resource] {
    let sources = sourceFiles(in: project)
        .filter { ref in
            // exclude xml/html files as sources; consider them both source and resource
            // TODO: this is a bit of a slippery slope; where do we draw the line?
            //       stuff like JSON and YAML probably fits here as well, etc. etc. ...
            ref.kind != "text.xml" && ref.url.pathExtension != "xml" && ref.kind != "text.html"
                && ref.url.pathExtension != "html"
        }
    return project.files
        .filter { ref in
            // TODO: specific exclusions? e.g. "archive.ar"/"a", ".whatever" etc
            ref.hasTargetMembership && ref.kind != "folder.assetcatalog"  // not an assetcatalog
                && ref.url.pathExtension != "xcassets"  // not an assetcatalog
                && ref.kind != "wrapper.framework"  // not a dynamic framework
                && ref.url.pathExtension != "a"  // not a static library
                && ref.url.pathExtension != "xcconfig"  // not xcconfig
                && !ref.url.lastPathComponent.hasPrefix(".")  // not a hidden file
                && !sources.contains { sourceRef -> Bool in
                    ref.url == sourceRef.url  // not a source-file
                }
        }
        .map { ref in
            Resource(at: ref.url)
        }
}

extension URL {
    /**
     A Boolean that is `true` if the URL points to a directory containing a "Contents.json" file.
     */
    fileprivate var isAssetURL: Bool {
        FileManager.default.fileExists(
            atPath: appendingPathComponent("Contents.json").path
        )
    }
}

extension String {
    fileprivate func removingOccurrences(matchingExpressions expressions: [NSRegularExpression])
        -> String
    {
        var str = self
        for expr in expressions {
            var match = expr.firstMatch(
                in: str,
                range: NSRange(location: 0, length: str.utf16.count)
            )
            while match != nil {
                str.replaceSubrange(Range(match!.range, in: str)!, with: "")
                match = expr.firstMatch(
                    in: str,
                    range: NSRange(location: 0, length: str.utf16.count)
                )
            }
        }
        return str
    }
}

private func assetURLs(at url: URL) -> [URL] {
    guard
        let dirEnumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
    else {
        return []
    }

    return
        dirEnumerator.map { item in
            item as! URL
        }
        .filter { url in
            url.isDirectory && url.isAssetURL && !url.pathExtension.isEmpty
        }
}

private func assetFiles(in project: XcodeProject) -> [Resource] {
    project.files
        .filter { ref in
            ref.kind == "folder.assetcatalog" || ref.url.pathExtension == "xcassets"
        }
        .flatMap { ref in
            assetURLs(at: ref.url)
                .map { assetUrl in
                    Resource(at: assetUrl)
                }
        }
}

private enum SourcePattern {
    static let blockComments =
        try! NSRegularExpression(
            pattern:
                // note the #..# to designate a raw string, allowing the \* literal
                #"/\*"#  // starting point of a block comment
                + ".*?"  // anything between, lazily
                + #"\*/"#,  // ending point of a block comment
            options: [.dotMatchesLineSeparators]
        )
    static let lineComments =
        try! NSRegularExpression(
            pattern:
                "(?<!:)"  // avoid any case where the previous character is ":" (i.e. skipping URLs)
                + "//"  // starting point of a single-line comment
                + "[^\n\r]*?"  // anything following that is not a newline
                + "(?:[\n\r]|$)",  // until reaching end of string or a newline
            options: [.anchorsMatchLines]
        )
    static let htmlComments =
        try! NSRegularExpression(
            pattern:
                // strip HTML/XML comments
                "<!--.+?-->",
            options: [.dotMatchesLineSeparators]
        )
    static let appFonts =
        try! NSRegularExpression(
            pattern:
                // strip this particular and iOS specific plist-entry;
                // the reasoning is that these font resources should not be considered "in-use"
                // just by being defined in this plist entry- only if they also appear elsewhere
                "<key>UIAppFonts</key>.+?</array>",
            options: [.dotMatchesLineSeparators]
        )
}

// TODO: optionally include some info, Any? for printout under DEBUG/verbose
public typealias ExaminationProgressCallback = (Int, Int, String?) -> Void

public func examine(
    project: XcodeProject,
    for defect: Defect,
    progress: ExaminationProgressCallback? = nil
) -> Diagnosis? {
    switch defect {
    case .nonExistentFiles:
        let files = nonExistentFiles(in: project)
        if !files.isEmpty {
            let paths = files.map { ref in
                ref.path
            }
            return Diagnosis(
                conclusion: "non-existent files",
                help: """
                    These files are not present on the file system and could have been moved or removed.
                    In either case, each reference should be resolved or removed from the project.
                    """,
                cases: paths
            )
        }
    case .nonExistentPaths:
        let groups = nonExistentGroups(in: project)
        if !groups.isEmpty {
            let paths = groups.map { ref in
                "\(ref.path!): \"\(ref.projectUrl.absoluteString)\""
            }
            return Diagnosis(
                conclusion: "non-existent group paths",
                // TODO: word this differently; a non-existent path is typically harmless:
                //
                //       "This is typically seen in projects under version-control, where a
                //       contributor has this folder on their local copy, but, if empty,
                //       is not added to version-control, leaving other contributors with a group
                //       in Xcode, but no folder on disk to go with it."
                //
                //       however, there's also another case where occurs:
                //       this is similarly harmless (typically), but is objectively a project smell:
                //       if moving things around/messing with project files directly; e.g.
                //       a group is both named and pathed (incorrectly), with child groups
                //       overriding the incorrect path by using SOURCE_ROOT or similar
                //       so ultimately everything works fine in Xcode, even though there is a bad path
                help: """
                    If not corrected, these paths can cause tools to erroneously
                    map children of each group to non-existent files.
                    """,
                cases: paths
            )
        }
    case .corruptPropertyLists:
        let propertyLists = propertyListReferences(in: project)

        let corruptedPropertyLists =
            propertyLists
            .enumerated()
            .compactMap({ n, file -> (FileReference, String)? in
                #if DEBUG
                    progress?(n + 1, propertyLists.count, file.url.lastPathComponent)
                #else
                    progress?(n + 1, propertyLists.count, nil)
                #endif

                do {
                    _ = try PropertyListSerialization.propertyList(
                        from: try Data(contentsOf: file.url),
                        format: nil
                    )
                } catch let error as NSError {
                    let additionalInfo: String
                    if let helpfulErrorMessage = error.userInfo[NSDebugDescriptionErrorKey]
                        as? String
                    {
                        // this is typically along the lines of:
                        //  "Value missing for key inside <dict> at line 7"
                        additionalInfo = helpfulErrorMessage
                    } else {
                        // this is typically more like:
                        //  "The data couldn’t be read because it isn’t in the correct format."
                        additionalInfo = error.localizedDescription
                    }
                    return (file, additionalInfo)
                }
                return nil
            })

        progress?(propertyLists.count, propertyLists.count, nil)

        if !corruptedPropertyLists.isEmpty {
            let paths = corruptedPropertyLists.map { file, additionalInfo in
                "\(file.path): \(additionalInfo)"
            }
            return Diagnosis(
                conclusion: "corrupted plists",
                help: """
                    These files must be fixed manually using any plain-text editor.
                    """,
                cases: paths
            )
        }
    case .danglingFiles:
        let files = danglingFiles(in: project)
        if !files.isEmpty {
            let paths = files.map { file in
                file.path
            }
            return Diagnosis(
                conclusion: "files not included in any target",
                help: """
                    These files are never being compiled and might not be used;
                    consider whether they should be removed.
                    """,
                cases: paths
            )
        }
    case .unusedResources(let strippingComments):
        // find asset files; i.e. files inside asset catalogs, excluding those referenced by certain
        // build settings as these typically won't be found using full-text search in sourcefiles
        let assets = assetFiles(in: project)
            .filter { asset in
                // note that we should only need to check `name` here; other variants do not seem
                // to be referenced for these settings
                !project.referencesAssetForCatalogCompilation(named: asset.name)
            }
        var resources = resourceFiles(in: project) + assets
        // full-text search every source-file
        let sources = sourceFiles(in: project)
        for (n, source) in sources.enumerated() {
            #if DEBUG
                progress?(n + 1, sources.count, source.url.lastPathComponent)
            #else
                progress?(n + 1, sources.count, nil)
            #endif

            let fileContents: String
            do {
                fileContents = try String(contentsOf: source.url)
            } catch {
                continue
            }

            var patterns: [NSRegularExpression] = []
            if let kind = source.kind, kind.starts(with: "sourcecode") {
                if strippingComments {
                    patterns.append(contentsOf: [
                        // note prioritized order: strip block comments before line comments
                        SourcePattern.blockComments, SourcePattern.lineComments,
                    ])
                }
            } else if source.kind == "text.xml" || source.kind == "text.html"
                || source.url.pathExtension == "xml" || source.url.pathExtension == "html"
            {
                patterns.append(SourcePattern.htmlComments)
            } else if source.kind == "text.plist.xml" || source.url.pathExtension == "plist",
                project.referencesPropertyListAsInfoPlist(named: source)
            {
                patterns.append(SourcePattern.appFonts)
            }

            let strippedFileContents =
                fileContents
                .removingOccurrences(matchingExpressions: patterns)

            resources.removeAll { resource in
                // TODO: case-sensitive search, but UIImage/Font(named: might not be case sensitive
                //       - would have to lower-case entire sourcefile too; can't catch mixed case errors otherwise
                for resourceName in resource.nameVariants {
                    let searchStrings: [String]
                    if let kind = source.kind, kind.starts(with: "sourcecode") {
                        // search for quoted strings in anything considered sourcecode;
                        // e.g. `UIImage(named: "Icon10")`
                        // however, consider the case:
                        //      `loadspr("res/monster.png")`
                        // here, the resource is actually "monster.png", but a build/copy phase
                        // has moved the resource to another destination; this means searching
                        //      `"monster.png"`
                        // won't work out as we want it to; instead, we can just try to match
                        // the end, which should work out no matter the destination, while
                        // still being decently specific; e.g.
                        //      `/monster.png"`
                        searchStrings = ["\"\(resourceName)\"", "/\(resourceName)\""]
                    } else if source.kind == "text.plist.xml" || source.url.pathExtension == "plist"
                    {
                        // search property-lists; typically only node contents
                        // e.g. "<key>Icon10</key>"
                        searchStrings = [">\(resourceName)<"]
                    } else {
                        // search any other text-based source; quoted strings and node content
                        // e.g. "<key>Icon10</key>"
                        //      "<key attr="Icon10">asdasd</key>"
                        searchStrings = ["\"\(resourceName)\"", ">\(resourceName)<"]
                    }
                    for searchString in searchStrings {
                        if strippedFileContents.contains(searchString) {
                            // resource seems to be used; remove and don't search further for this
                            return true
                        }
                    }
                }
                // resource seems to be unused; don't remove and keep searching for usages
                return false
            }
        }

        progress?(sources.count, sources.count, nil)

        if !resources.isEmpty {
            let unusedResourceNames = resources.map { resource -> String in
                if resource.url.isAssetURL {
                    return resource.name
                }
                return resource.fileName
            }
            return Diagnosis(
                conclusion: "unused resources",
                help: """
                    These files might not be used; consider whether they should be removed.
                    Note that this diagnosis is prone to false-positives as it can't realistically
                    detect all usage patterns with certainty. Proceed with caution.
                    """,
                cases: unusedResourceNames
            )
        }
    case .emptyAssets:
        let assets = assetFiles(in: project)

        let colorAssets = assets.filter { asset in
            asset.url.pathExtension == "colorset"
        }

        var n: Int = 0
        let total: Int = assets.count

        let emptyColorAssets = colorAssets.filter { asset in
            n = n + 1
            #if DEBUG
                progress?(n, total, asset.url.lastPathComponent)
            #else
                progress?(n, total, nil)
            #endif
            do {
                let string = try String(
                    contentsOf: asset.url.appendingPathComponent("Contents.json")
                )
                if let data = string.data(using: .utf8) {
                    // see https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/Named_Color.html#//apple_ref/doc/uid/TP40015170-CH59-SW1
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let colors = json["colors"] as? [[String: Any]]
                    {
                        for listing in colors {
                            if let color = listing["color"] as? [String: Any], !color.isEmpty {
                                return false
                            }
                        }
                    }
                }
            } catch {
                // potentially corrupt; consider this empty for now
            }
            return true
        }

        let fileAssets = assets.filter { asset in
            !colorAssets.contains(asset)
        }

        let emptyFileAssets = fileAssets.filter { asset in
            n = n + 1
            #if DEBUG
                progress?(n, total, asset.url.lastPathComponent)
            #else
                progress?(n, total, nil)
            #endif
            // find all asset sets with no additional files other than a "Contents.json"
            // (assuming that one always exists in asset sets)
            return
                (try?
                FileManager.default
                .contentsOfDirectory(
                    at: asset.url,
                    includingPropertiesForKeys: nil
                )
                .count < 2) ?? false
        }

        let emptyAssets = emptyFileAssets + emptyColorAssets

        progress?(total, total, nil)

        if !emptyAssets.isEmpty {
            let emptyAssetNames = emptyAssets.map { asset in
                asset.name
            }
            return Diagnosis(
                conclusion: "empty assets",
                help: """
                    These asset sets contain zero actual resources and might be redundant;
                    consider whether they should be removed.
                    """,
                cases: emptyAssetNames
            )
        }
    case .emptyGroups:
        let groups = emptyGroups(in: project)
        if !groups.isEmpty {
            let paths = groups.map { ref in
                "\(ref.projectUrl.absoluteString)"
            }
            return Diagnosis(
                conclusion: "empty groups",
                help: """
                    These groups contain zero children and might be redundant;
                    consider whether they should be removed.
                    """,
                cases: paths
            )
        }
    case .emptyTargets:
        let targets = emptyTargets(in: project)
        if !targets.isEmpty {
            let names = targets.map { product in
                product.name
            }
            return Diagnosis(
                conclusion: "empty targets",
                help: """
                    These targets do not compile any sources and might be redundant;
                    consider whether they should be removed.
                    """,
                cases: names
            )
        }
    }
    return nil
}
