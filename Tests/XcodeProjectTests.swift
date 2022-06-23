//
//  XcodeProjectTests.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//

import Foundation
import XCTest

@testable import XCDoctor

// note that paths in these tests assumes `$ swift test` from the root of the project;
// it does _not_ work when run from Xcode; some might still pass, but most will fail
func projectUrl(for defect: Defect) -> URL {
    URL(fileURLWithPath: "Tests/Subjects/")
        .appendingPathComponent(
            "\(defect)/xcdoctor.xcodeproj"
        )
}

class XcodeProjectTests: XCTestCase {
    func testProjectNotFoundInNonExistentPath() {
        let result =
            XcodeProject
            .openAndEvaluate(from: URL(fileURLWithPath: "~/Some/Project.xcodeproj"))
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(
                error as! XcodeProjectError,
                XcodeProjectError.notFound(amongFilesInDirectory: false)
            )
        }
    }

    func testProjectNotFoundInNonExistentDirectory() {
        let result = XcodeProject.openAndEvaluate(from: URL(fileURLWithPath: "~/Some/Place/"))
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(
                error as! XcodeProjectError,
                XcodeProjectError.notFound(amongFilesInDirectory: true)
            )
        }
    }

    func testProjectNotFoundInDirectory() {
        // assumes this directory is kept rid of .xcodeprojs
        let result = XcodeProject.openAndEvaluate(from: URL(fileURLWithPath: "Tests/Subjects/"))
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(
                error as! XcodeProjectError,
                XcodeProjectError.notFound(amongFilesInDirectory: true)
            )
        }
    }

    func testProjectFound() {
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: .nonExistentFiles))
        XCTAssertNoThrow(try result.get())
    }

    func testFileReferenceResolution() {
        let condition: Defect = .nonExistentFiles
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: condition))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        XCTAssert(project.files.count == 1)
        XCTAssertEqual(
            project.files.first!.url,
            projectUrl(for: condition)
                .deletingLastPathComponent()
                .appendingPathComponent("xcdoctor")
                .appendingPathComponent("main.swift")
        )
    }

    func testMissingFile() {
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: .nonExistentFiles))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        let diagnosis = examine(project: project, for: .nonExistentFiles)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases.count == 1)
    }

    func testMissingFolder() {
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: .nonExistentPaths))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        let diagnosis = examine(project: project, for: .nonExistentPaths)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases.count == 1)
    }

    func testCorruptPlist() {
        let condition: Defect = .corruptPropertyLists
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: condition))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        let diagnosis = examine(project: project, for: condition)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases.count == 1)
    }

    func testDanglingFile() {
        let condition: Defect = .danglingFiles
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: condition))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        let diagnosis = examine(project: project, for: condition)
        XCTAssertNotNil(diagnosis)
        XCTAssertNotNil(diagnosis!.cases)
        XCTAssert(diagnosis!.cases.count == 1)
    }

    func testEmptyGroups() {
        let condition: Defect = .emptyGroups
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: condition))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        let diagnosis = examine(project: project, for: condition)
        guard let cases = diagnosis?.cases else {
            XCTFail()
            return
        }
        guard cases.count == 2 else {
            XCTFail()
            return
        }
        XCTAssert(cases.contains("xcdoctor/a"))
        XCTAssert(cases.contains("xcdoctor/b/c/d"))
    }

    func testEmptyTargets() {
        let condition: Defect = .emptyTargets
        let result = XcodeProject.openAndEvaluate(from: projectUrl(for: condition))
        guard let project = try? result.get() else {
            XCTFail()
            return
        }
        let diagnosis = examine(project: project, for: condition)
        guard let cases = diagnosis?.cases else {
            XCTFail()
            return
        }
        guard cases.count == 2 else {
            XCTFail()
            return
        }
        XCTAssert(cases.contains("xcdoctor"))
        XCTAssert(cases.contains("empty"))
    }
}
