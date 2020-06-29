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
    func projectUrl(for defect: Defect) -> URL {
        // note that this assumes `$ swift test` from the root of the project;
        // it does not work when run from Xcode
        return URL(fileURLWithPath: "Tests/Subjects/")
            .appendingPathComponent(
                "\(defect)/xcdoctor.xcodeproj/project.pbxproj")
    }

    func testProjectNotFound() {
        XCTAssertNil(XcodeProject(from:
            // assuming this path does not exist!
            URL(fileURLWithPath: "~/Some/Project.xcodeproj")))
    }

    func testProjectFound() {
        let project = XcodeProject(
            from: projectUrl(for: .nonExistentFiles))!
        XCTAssertNotNil(project)
    }

    func testFileUrls() {
        let project = XcodeProject(
            from: projectUrl(for: .nonExistentFiles))!
        XCTAssert(project.files.count == 1)
    }

    func testMissingFile() {
        let project = XcodeProject(
            from: projectUrl(for: .nonExistentFiles))!
        let diagnosis = examine(project: project, for: .nonExistentFiles)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases!.count == 1)
    }

    func testCorruptPlist() {
        let project = XcodeProject(
            from: projectUrl(for: .corruptPropertyLists))!
        let diagnosis = examine(project: project, for: .corruptPropertyLists)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases!.count == 1)
    }

    func testDanglingFile() {
        let project = XcodeProject(
            from: projectUrl(for: .danglingFiles))!
        let diagnosis = examine(project: project, for: .danglingFiles)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases!.count == 1)
    }
}
