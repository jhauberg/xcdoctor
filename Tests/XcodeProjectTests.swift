//
//  XcodeProjectTests.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//

import XCTest
@testable import XCDoctor

import Foundation

class XcodeProjectTests: XCTestCase {
    func testFileNotFound() {
        XCTAssertNil(XcodeProject(from:
            URL(fileURLWithPath: "~/Some/Project.xcodeproj")))
    }
}
