//
//  main.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation
import XCDoctor

var outputStream = DiagnosticOutputStream()

func printdiag(text: String, kind: Diagnostic = .information) {
    outputStream.kind = kind
    // TODO: some debug validation of diagnostic messages; e.g.
    //         .important   should not be capitalized, and should not end with period
    //         .information should be capitalized and end with period
    let prefix = "doctor:"
    var diagnostic: String = text
    if kind == .important {
        diagnostic = "\(prefix) \(diagnostic)"
    }
    if outputStream.supportsColor {
        switch kind {
        case .information:
            break // no color
        case .important:
            diagnostic = "\u{001B}[0;31m\(diagnostic)\u{001B}[0m"
        case .note:
            diagnostic = "\u{001B}[0;33m\(diagnostic)\u{001B}[0m"
        }
    }
    print(diagnostic, to: &outputStream)
}

import ArgumentParser

struct Doctor: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "xcdoctor",
        version: "0.3.0"
    )

    @Argument(help:
        """
        A path to an Xcode project file.

        You can put in a path to a directory to automatically
        look for a project at that location, or "." to look
        for a project in the current working directory.
        """)
    var xcodeproj: String

    @Flag(name: .shortAndLong, help: "Show diagnostic messages.")
    var verbose: Bool = false

    mutating func run() throws {
        let searchUrl: URL
        if NSString(string: xcodeproj).isAbsolutePath {
            searchUrl = URL(fileURLWithPath: xcodeproj)
        } else {
            searchUrl = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(xcodeproj)
        }

        let projectUrl: URL
        if searchUrl.hasDirectoryPath {
            let files = try FileManager.default.contentsOfDirectory(
                atPath: searchUrl.standardized.path)
            if let xcodeProjectFile = files.first(where: { file -> Bool in
                file.hasSuffix("xcodeproj")
            }) {
                projectUrl = searchUrl.appendingPathComponent(xcodeProjectFile)
            } else {
                printdiag(text: "\(searchUrl.standardized.path): no projects found")
                throw ExitCode.failure
            }
        } else {
            projectUrl = searchUrl
        }

        if !FileManager.default.fileExists(atPath: projectUrl.standardized.path) {
            printdiag(text: "\(projectUrl.standardized.path): project not found")
            throw ExitCode.failure
        }

        if projectUrl.pathExtension != "xcodeproj" {
            printdiag(text: "\(projectUrl.standardized.path): file is not an Xcode project")
            throw ExitCode.failure
        }

        let pbxUrl = projectUrl.appendingPathComponent("project.pbxproj")

        if !FileManager.default.fileExists(atPath: pbxUrl.standardized.path) {
            printdiag(text: "\(projectUrl.standardized.path): unsupported Xcode project format")
            throw ExitCode.failure
        }

        guard let project = XcodeProject(from: pbxUrl) else {
            printdiag(text: "\(projectUrl.standardized.path): unsupported Xcode project format")
            throw ExitCode.failure
        }
        // order examinations based on importance, so that the most important is run last;
        // this may seem counter-intuitive, but in most cases, what you will read first
        // is actually the output that came last (especially for long/many diagnoses)
        // so with that assumption, it makes sense to order in such a way that
        // you read from bottom-to-top and clear out defects in that order
        // so, for example, nonExistentFiles should be cleared before danglingFiles,
        // as that likely has a cascading effect throughout previous diagnoses
        let conditions: [Defect] = [
            .danglingFiles,
            .unusedResources,
            .corruptPropertyLists,
            .nonExistentFiles,
            .nonExistentPaths,
        ]
        for condition in conditions {
            if verbose {
                var diagnostic = "Examining for \(condition) ... "
                if condition == .unusedResources {
                    diagnostic += "This may take a while"
                }
                printdiag(text: diagnostic)
            }
            if let diagnosis = examine(project: project, for: condition) {
                if let references = diagnosis.cases?.sorted() {
                    for reference in references {
                        printdiag(text: reference, kind: .note)
                    }
                }
                printdiag(text: diagnosis.conclusion, kind: .important)
                if let supplemental = diagnosis.help {
                    printdiag(text: supplemental)
                }
            }
        }

        throw ExitCode.success
    }
}

Doctor.main()
