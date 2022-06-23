//
//  DiagnosisTests.swift
//  XCDoctorTests
//
//  Created by Jacob Hauberg Hansen on 14/07/2020.
//

import Foundation
import XCTest

@testable import XCDoctor

class DiagnosisTests: XCTestCase {
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
