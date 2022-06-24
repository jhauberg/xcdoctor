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
    public let cases: [String]
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
            !ref.hasTargetMembership
                && !ref.isHeaderFile
                && (ref.isSourceFile
                    || (ref.kind == "folder.assetcatalog" || ref.url.pathExtension == "xcassets"
                        || ref.kind == "sourcecode.metal"))
        }
        .filter { ref in
            if ref.kind == "text.plist.xml" || ref.url.pathExtension == "plist" {
                return !project.referencesPropertyListAsInfoPlist(named: ref)
            }
            return true
        }
}

private func sourceFiles(in project: XcodeProject) -> [FileReference] {
    return project.files.filter { ref in
        ref.isSourceFile  // file is compiled in one way or another
            && !ref.url.isDirectory  // file is text-based; i.e. not a directory
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
            // certain files should be considered both source and resource; e.g. xibs, storyboards
            // (note that even if excluded here, they will still be represented as sources later)
            // TODO: this is a bit of a slippery slope; where do we draw the line?
            //       stuff like JSON and YAML probably fits here as well, etc. etc. ...
            ref.kind != "text.xml" && ref.url.pathExtension != "xml"  // allow plain xml
                && ref.kind != "text.html" && ref.url.pathExtension != "html"  // allow plain html
                && ref.kind != "file.storyboard" && ref.url.pathExtension != "storyboard"  // allow storyboards
                && ref.kind != "file.xib" && ref.url.pathExtension != "xib"  // allow xibs
                && ref.url.pathExtension != "nib"  // allow nibs
        }
    return project.files
        .filter { ref in
            // a resource is any file included in a project that is not considered a source file
            // while also matching the requirements below
            // TODO: specific exclusions? e.g. "archive.ar"/"a", ".whatever" etc
            ref.hasTargetMembership  // must be included in a build phase for any target
                && ref.kind != "folder.assetcatalog"  // not an assetcatalog
                && ref.url.pathExtension != "xcassets"  // not an assetcatalog
                && ref.kind != "text.plist.strings"  // not a strings file
                && ref.url.pathExtension != "strings"  // not a strings file
                && ref.kind != "wrapper.framework"  // not a framework
                && ref.kind != "wrapper.xcframework"  // not a framework
                && ref.url.pathExtension != "a"  // not a static library
                && ref.url.pathExtension != "xcconfig"  // not xcconfig
                && ref.kind != "sourcecode.metal"  // not a Metal shader
                && !ref.url.lastPathComponent.hasPrefix(".")  // not a hidden file
                && !sources.contains { sourceRef -> Bool in
                    ref.url == sourceRef.url  // not a source-file
                }
        }
        .map { ref in
            Resource(at: ref.url)
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
            url.isDirectory && url.isAssetDirectory && !url.pathExtension.isEmpty
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

private struct CorruptPropertyListCase {
    let file: FileReference
    let reason: String
}

private func findCorruptPropertyLists(
    in project: XcodeProject,
    progress: ExaminationProgressCallback? = nil
) -> [CorruptPropertyListCase] {
    let propertyLists = propertyListReferences(in: project).filter { ref in
        FileManager.default.fileExists(atPath: ref.path)
    }

    let corruptedPropertyLists =
        propertyLists
        .enumerated()
        .compactMap({ n, file -> CorruptPropertyListCase? in
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
                return CorruptPropertyListCase(file: file, reason: additionalInfo)
            }
            return nil
        })

    progress?(propertyLists.count, propertyLists.count, nil)

    return corruptedPropertyLists
}

private func findEmptyAssets(
    in project: XcodeProject,
    progress: ExaminationProgressCallback? = nil
) -> [Resource] {
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

    let missingFileAssets = fileAssets.filter { asset in
        n = n + 1
        #if DEBUG
            progress?(n, total, asset.url.lastPathComponent)
        #else
            progress?(n, total, nil)
        #endif
        guard
            let fileCount = try? FileManager.default
                .contentsOfDirectory(
                    at: asset.url,
                    includingPropertiesForKeys: nil
                )
                .count
        else {
            fatalError()
        }
        // find all asset sets with no additional files other than a "Contents.json"
        // (assuming that one always exists in asset sets)
        return fileCount < 2
    }

    let emptyAssets = missingFileAssets + emptyColorAssets

    progress?(total, total, nil)

    return emptyAssets
}

private func findUnusedResources(
    in project: XcodeProject,
    stripCommentsInSourceFiles: Bool = true,
    progress: ExaminationProgressCallback? = nil
) -> [Resource] {
    // find asset files; i.e. files inside asset catalogs, excluding those referenced by certain
    // build settings as these typically won't be found using full-text search in sourcefiles
    let assets = assetFiles(in: project)
        .filter { asset in
            // note that we should only need to check `name` here; other variants do not seem
            // to be referenced for these settings
            !project.referencesAssetForCatalogCompilation(named: asset.name)
        }
    var resources =
        resourceFiles(in: project)
        .filter { resource in
            // exclude storyboards explicitly referenced in certain build settings
            resource.url.pathExtension != "storyboard"
                || !project.referencesStoryboardAsPreset(named: resource.name)
        } + assets
    resources.removeAll { res in
        !FileManager.default.fileExists(atPath: res.path) // don't process non-existent files
    }
    let sources = sourceFiles(in: project).filter { ref in
        FileManager.default.fileExists(atPath: ref.path)
    }
    // full-text search every source-file
    let sources = sourceFiles(in: project)
    for (n, source) in sources.enumerated() {
        #if DEBUG
            progress?(n + 1, sources.count, source.url.lastPathComponent)
        #else
            progress?(n + 1, sources.count, nil)
        #endif

        guard let fileContents = try? String(contentsOf: source.url) else {
            fatalError()
        }

        var patterns: [NSRegularExpression] = []
        if let kind = source.kind, kind.starts(with: "sourcecode") {
            if stripCommentsInSourceFiles {
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
                // list of strings to search for; if any matches move on to next resource
                let searchStrings: [String]
                if let kind = source.kind, kind.starts(with: "sourcecode") {
                    // search for quoted strings in anything considered sourcecode;
                    if resource.url.isAssetDirectory {
                        // always similar to `UIImage(named: "Icon10")`
                        searchStrings = ["\"\(resourceName)\""]
                    } else {
                        // could also be part of a path, e.g. `load("data/machines.json")`
                        searchStrings = ["\"\(resourceName)\"", "/\(resourceName)\""]
                    }
                } else if source.kind == "text.plist.xml" || source.url.pathExtension == "plist" {
                    // search property-lists; typically only node contents
                    // e.g. "<key>Icon10</key>"
                    searchStrings = [">\(resourceName)<"]
                } else {
                    // search any other text-based source; quoted strings and node content
                    // e.g. "<key>Icon10</key>"
                    //      "<key attr="Icon10">asdasd</key>"
                    searchStrings = [">\(resourceName)<", "\"\(resourceName)\""]
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
    // any remaining resource is deemed unused
    return resources
}

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
                conclusion: "non-existent files (\(files.count))",
                help: """
                    These files are not present on the file system and could have been moved or removed.
                    In either case, each reference should be resolved or removed from the project.
                    """,
                cases: paths.sorted()
            )
        }
    case .nonExistentPaths:
        let groups = nonExistentGroups(in: project)
        if !groups.isEmpty {
            let paths = groups.map { ref in
                "\(ref.path!): \"\(ref.projectUrl.absoluteString)\""
            }
            return Diagnosis(
                conclusion: "non-existent group paths (\(groups.count))",
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
                cases: paths.sorted()
            )
        }
    case .corruptPropertyLists:
        let cases = findCorruptPropertyLists(in: project, progress: progress)
        if !cases.isEmpty {
            let paths = cases.map { condition in
                "\(condition.file.path): \(condition.reason)"
            }
            return Diagnosis(
                conclusion: "corrupted plists (\(cases.count))",
                help: """
                    These files must be fixed manually using any plain-text editor.
                    """,
                cases: paths.sorted()
            )
        }
    case .danglingFiles:
        let files = danglingFiles(in: project)
        if !files.isEmpty {
            let paths = files.map { file in
                file.path
            }
            return Diagnosis(
                conclusion: "files not included in any target (\(files.count))",
                help: """
                    These files are never being compiled and might not be used;
                    consider whether they should be removed.
                    """,
                cases: paths.sorted()
            )
        }
    case .unusedResources(let strippingComments):
        let resources = findUnusedResources(
            in: project,
            stripCommentsInSourceFiles: strippingComments,
            progress: progress
        )
        if !resources.isEmpty {
            let unusedResources: [(String, Int)] = resources.map { resource in
                let fileSizeInBytes: Int
                if resource.url.isDirectory {
                    guard
                        let urls =
                            FileManager.default.enumerator(
                                at: resource.url,
                                includingPropertiesForKeys: nil
                            )?
                            .allObjects as? [URL]
                    else {
                        fatalError()
                    }
                    fileSizeInBytes = urls.reduce(0) { partialResult, url in
                        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                            + partialResult
                    }

                } else {
                    guard let attr = try? resource.url.resourceValues(forKeys: [.fileSizeKey]),
                        let fileSize = attr.fileSize
                    else {
                        fatalError()
                    }
                    fileSizeInBytes = fileSize
                }
                let name: String
                if resource.url.isAssetDirectory {
                    name = resource.name
                } else {
                    name = resource.fileName
                }
                return (name, fileSizeInBytes)
            }
            let fileSizeFormatter = ByteCountFormatter()
            fileSizeFormatter.countStyle = .file
            let cases: [String] =
                unusedResources
                .sorted(by: { (lhs, rhs) in
                    let (name, fileSize) = lhs
                    let (otherName, otherFileSize) = rhs
                    return (fileSize, name) < (otherFileSize, otherName)
                })
                .map { name, fileSizeInBytes in
                    if fileSizeInBytes > 0 {
                        let prettyFileSize = fileSizeFormatter.string(
                            fromByteCount: Int64(fileSizeInBytes)
                        )
                        return "\(name) (\(prettyFileSize))"
                    }
                    return name
                }
            let totalFileSizeInBytes = unusedResources.reduce(0) { partialResult, nextResult in
                let (_, fileSize) = nextResult
                return partialResult + fileSize
            }
            let prettyTotalFileSize =
                totalFileSizeInBytes > 0
                ? fileSizeFormatter.string(
                    fromByteCount: Int64(totalFileSizeInBytes)
                ) : "space"
            return Diagnosis(
                conclusion: "unused resources (\(unusedResources.count))",
                help: """
                    These files might not be used; consider whether they should be removed to free up \(prettyTotalFileSize).
                    Note that this diagnosis is prone to false-positives as it can't realistically
                    detect all usage patterns with certainty. Proceed with caution.
                    """,
                cases: cases
            )
        }
    case .emptyAssets:
        let assets = findEmptyAssets(in: project, progress: progress)
        if !assets.isEmpty {
            let emptyAssetNames = assets.map { asset in
                asset.name
            }
            return Diagnosis(
                conclusion: "empty assets (\(assets.count))",
                help: """
                    These asset sets contain zero actual resources and might be redundant;
                    consider whether they should be removed.
                    """,
                cases: emptyAssetNames.sorted()
            )
        }
    case .emptyGroups:
        let groups = emptyGroups(in: project)
        if !groups.isEmpty {
            let paths = groups.map { ref in
                "\(ref.projectUrl.absoluteString)"
            }
            return Diagnosis(
                conclusion: "empty groups (\(groups.count))",
                help: """
                    These groups contain zero children and might be redundant;
                    consider whether they should be removed.
                    """,
                cases: paths.sorted()
            )
        }
    case .emptyTargets:
        let targets = emptyTargets(in: project)
        if !targets.isEmpty {
            let names = targets.map { product in
                product.name
            }
            return Diagnosis(
                conclusion: "empty targets (\(targets.count))",
                help: """
                    These targets do not compile any sources and might be redundant;
                    consider whether they should be removed.
                    """,
                cases: names.sorted()
            )
        }
    }
    return nil
}
