//
//  XcodeProjectTests.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//

@testable import XCDoctor

import Foundation
import XCTest

class XcodeProjectTests: XCTestCase {
    func testProjectNotFound() {
        XCTAssertNil(XcodeProject(from:
            URL(fileURLWithPath: "~/Some/Project.xcodeproj")))
    }

    func testProjectFound() {
        // note that this path assumes `$ swift test` from the root of the project;
        // it does not work when run from Xcode
        XCTAssertNotNil(XcodeProject(from:
            URL(fileURLWithPath: "Tests/Subjects/missing-file.xcodeproj/project.pbxproj")))
    }

    func testFileUrls() {
        let project = XcodeProject(from:
            URL(fileURLWithPath: "Tests/Subjects/missing-file.xcodeproj/project.pbxproj"))!
        XCTAssert(project.files.count == 1)
    }

    func testMissingFile() {
        let project = XcodeProject(from:
            URL(fileURLWithPath: "Tests/Subjects/missing-file.xcodeproj/project.pbxproj"))!
        let diagnosis = examine(project: project, for: .nonExistentFiles)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases!.count == 1)
    }
}
