//
//  main.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

var outputStream = DiagnosticOutputStream()

func printdiag(text: String, kind: DiagnosticOutputStream.Diagnostic = .information) {
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
            // TODO: revisit coloring; this uses bright palette
            diagnostic = "\u{001B}[0;91m\(diagnostic)\u{001B}[0m"
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

        let pbxUrl = projectUrl.appendingPathComponent("project.pbxproj")

        if !FileManager.default.fileExists(atPath: pbxUrl.path) {
            printdiag(text: "unsupported Xcode project format", kind: .information)
            throw ExitCode.failure
        }

        if let project = XcodeProject(from: pbxUrl) {
            for diagnosis in examine(project: project, for: [
                .nonExistentFiles,
            ]) {
                if let references = diagnosis.cases {
                    for reference in references {
                        printdiag(text: reference, kind: .note)
                    }
                }
                printdiag(text: diagnosis.conclusion, kind: .important)
                if let supplemental = diagnosis.help {
                    printdiag(text: supplemental, kind: .information)
                }
            }
        } else {
            printdiag(text: "unsupported Xcode project format", kind: .information)
            throw ExitCode.failure
        }

        throw ExitCode.success
    }
}

Doctor.main()
