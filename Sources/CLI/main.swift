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
            diagnostic = "\u{1B}[0;31m\(diagnostic)\u{1B}[0m"
        case .note:
            diagnostic = "\u{1B}[0;33m\(diagnostic)\u{1B}[0m"
        }
    }
    print(diagnostic, to: &outputStream)
}

import ArgumentParser

struct Doctor: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "xcdoctor",
        version: "0.4.0"
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
        let url: URL
        if NSString(string: xcodeproj).isAbsolutePath {
            url = URL(fileURLWithPath: xcodeproj)
        } else {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(xcodeproj)
        }

        let opening: XcodeProject.EventCallback? = verbose ? { name in
            printdiag(text: "Opening \(name) ...")
        } : nil
        let evaluating: XcodeProject.EventCallback? = verbose ? { name in
            printdiag(text: "Evaluating \(name) ...")
        } : nil

        let project: XcodeProject
        switch XcodeProject.openAndEvaluate(
            from: url,
            beforeOpeningProject: opening,
            beforeEvaluatingProject: evaluating
        ) {
        case let .success(xcodeProject):
            project = xcodeProject
        case let .failure(error):
            switch error {
            case let .incompatible(reason):
                printdiag(text: "\(url.standardized.path): \(reason)")
            case let .notFound(amongFilesInDirectory):
                if amongFilesInDirectory {
                    printdiag(text: "\(url.standardized.path): no Xcode project found")
                } else {
                    printdiag(text: "\(url.standardized.path): Xcode project not found")
                }
            }
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
            .unusedResources,
            .emptyGroups,
            .danglingFiles,
            .emptyTargets,
            .corruptPropertyLists,
            .nonExistentFiles,
            .nonExistentPaths,
        ]
        for condition in conditions {
            if verbose {
                var diagnostic = "Examining for \(condition) ... \u{1B}[s" // save column at end for activity indication
                if condition == .unusedResources {
                    diagnostic += "This may take a while \u{1B}[s"
                }
                printdiag(text: diagnostic)
            }

            let indicateActivity: ExaminationProgressCallback? = verbose ? { finished in
                // TODO: consider doing a "[10/52]" kind of progress instead;
                //       that doesn't need to be cleared at end => simpler
                //       and it provides much more information besides just activity
                if finished {
                    printdiag(text: "\u{1B}[u\u{1B}[1A ") // clear the indicator by whitespace
                } else {
                    let c = Int.random(in: 0...1) == 0 ? "/" : "\\"
                    printdiag(text: "\u{1B}[u\u{1B}[1A\(c)") // move cursor to previous line at saved column
                }
            } : nil

            if let diagnosis = examine(project: project, for: condition, progress: indicateActivity) {
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
