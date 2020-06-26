//
//  main.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

final class DiagnosticOutputStream: TextOutputStream {
    enum Diagnostic {
        case important
        case information
        case note

        var stream: FileHandle {
            switch self {
            case .information:
                return .standardError
            case .important:
                return .standardOutput
            case .note:
                return .standardOutput
            }
        }

        /**
          Determine whether the output stream supports escape codes for applying colors.

          Output piped to a file that is not any of the standard file descriptors typically do not respond as a TTY.
         */
        var supportsColor: Bool {
            let tty = isatty(stream.fileDescriptor)

            guard Bool(truncating: tty as NSNumber) else {
                // terminal must respond as a TTY
                return false
            }

            return true
        }
    }

    /**
     Determine whether the terminal supports escape codes for applying colors.
     */
    var supportsColor: Bool {
        guard let term = getenv("TERM") else {
            // terminal must have declared $TERM
            return false
        }

        let name = String(cString: term)

        guard !name.isEmpty, name.lowercased() != "dumb" else {
            // $TERM must be anything but empty or "dumb", literally
            return false
        }

        guard kind.supportsColor else {
            return false
        }

        return true
    }

    var kind: Diagnostic = .information

    func write(_ string: String) {
        kind.stream.write(Data(string.utf8))
    }
}

var outputStream = DiagnosticOutputStream()

func printdiag(text: String, kind: DiagnosticOutputStream.Diagnostic = .information) {
    outputStream.kind = kind
    var diagnostic: String = text
    if kind == .important {
        diagnostic = "doctor: \(diagnostic)"
    }
    if outputStream.supportsColor {
        switch kind {
        case .information:
            break // no color
        case .important:
            diagnostic = "\u{001B}[0;91m\(diagnostic)\u{001B}[0m"
        case .note:
            diagnostic = "\u{001B}[0;33m\(diagnostic)\u{001B}[0m"
        }
    }
    print(diagnostic, to: &outputStream)
}

func parents(of reference: String, in groups: [String: Any])
    -> [String: Any] {
    let parents = groups.filter { group -> Bool in
        let groupObj = group.value as! [String: Any]
        let children = groupObj["children"] as! [String]
        return children.contains(reference)
    }

    return parents
}

func urls(in project: [String: Any], at rootUrl: URL) -> [URL] {
    var fileUrls: [URL] = []
    if let objects = project["objects"] as? [String: Any] {
        let fileReferences = objects.filter { (elem) -> Bool in
            if let obj = elem.value as? [String: Any] {
                // must be a file reference
                if let isa = obj["isa"] as? String, isa == "PBXFileReference",
                    // and it must have an associated type
                    let _ = obj["lastKnownFileType"] as? String {
                    return true
                }
            }
            return false
        }
        let groupReferences = objects.filter { (elem) -> Bool in
            if let obj = elem.value as? [String: Any] {
                if let isa = obj["isa"] as? String, isa == "PBXGroup" || isa == "PBXVariantGroup",
                    // and it must have children
                    let children = obj["children"] as? [String], !children.isEmpty {
                    return true
                }
            }
            return false
        }
        for file in fileReferences {
            let obj = file.value as! [String: Any]
            var path: String = obj["path"] as! String
            let sourceTree: String = obj["sourceTree"] as! String
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
                    if let parentPath = obj["path"] as? String {
                        path = "\(parentPath)/\(path)"
                    } else {
                        // non-folder group or root of hierarchy
                    }
                    parentReferences = parents(of: p.key, in: groupReferences)
                }
            default:
                fatalError()
            }
            fileUrls.append(
                rootUrl.appendingPathComponent(path))
        }
    }
    return fileUrls
}

import ArgumentParser

struct Doctor: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "xcdoctor",
        version: "0.1.0"
    )

    @Argument(help:
        // TODO: or a path to a directory containing an Xcode project file
        """
        A path to an Xcode project file.

        You can put in "." to look for a project in the current working directory.
        """)
    var xcodeproj: String

    @Flag(name: .shortAndLong, help: "Show diagnostic messages.")
    var verbose: Bool = false

    func validate() throws {
        // TODO: validate that xcodeproj is a path (maybe try making a URL?)
    }

    mutating func run() throws {
        let path: String

        if xcodeproj == "." {
            let files = try FileManager.default.contentsOfDirectory(atPath:
                FileManager.default.currentDirectoryPath)
            if let xcodeProjectFile = files.first(where: { file -> Bool in
                file.hasSuffix("xcodeproj")
            }) {
                path = xcodeProjectFile
            } else {
                printdiag(text: "no project found", kind: .information)
                throw ExitCode.failure
            }
        } else {
            path = xcodeproj
        }

        if !FileManager.default.fileExists(atPath: path) {
            printdiag(text: "project does not exist", kind: .information)
            throw ExitCode.failure
        }

        let projectUrl = URL(fileURLWithPath: path)

        if projectUrl.pathExtension != "xcodeproj" {
            printdiag(text: "file is not an Xcode project", kind: .information)
            throw ExitCode.failure
        }

        let rootUrl = projectUrl.deletingLastPathComponent()
        let pbxUrl = projectUrl.appendingPathComponent("project.pbxproj")

        if !FileManager.default.fileExists(atPath: pbxUrl.path) {
            printdiag(text: "unsupported Xcode project format", kind: .information)
            throw ExitCode.failure
        }

        do {
            let data = try Data(contentsOf: pbxUrl)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: .mutableContainersAndLeaves,
                format: &format
            )
            if let project = plist as? [String: Any] {
                let fileUrls = urls(in: project, at: rootUrl)
                let nonExistentFiles = fileUrls.filter { fileUrl -> Bool in
                    !FileManager.default.fileExists(atPath: fileUrl.path)
                }
                if !nonExistentFiles.isEmpty {
                    for nonExistentFile in nonExistentFiles {
                        printdiag(text: nonExistentFile.standardized.relativePath, kind: .note)
                    }
                    printdiag(text: "non-existent files are referenced in project", kind: .important)
                    printdiag(text: "File references to non-existent files should be removed from the project.", kind: .information)
                }
            }
        } catch {
            printdiag(text: "unsupported Xcode project format", kind: .information)
            throw ExitCode.failure
        }

        throw ExitCode.success
    }
}

Doctor.main()
