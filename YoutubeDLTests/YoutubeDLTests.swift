//
//  YoutubeDLTests.swift
//  YoutubeDLTests
//
//  Created by 안창범 on 2020/08/03.
//  Copyright © 2020 Jane Developer. All rights reserved.
//

import XCTest
@testable import YoutubeDL
@testable import Y

class YTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSeconds() throws {
        XCTAssertEqual(seconds(""), 0)
        XCTAssertEqual(seconds("1"), 1)
        XCTAssertEqual(seconds("03"), 3)
        XCTAssertEqual(seconds("32"), 32)
        XCTAssertEqual(seconds("321"), 321)
        XCTAssertEqual(seconds("3:21"), 3 * 60 + 21)
        XCTAssertEqual(seconds("3:2"), 3 * 60 + 2)
        XCTAssertEqual(seconds(":"), 0)
        XCTAssertEqual(seconds(":1"), 1)
        XCTAssertEqual(seconds("43:21"), 43 * 60 + 21)
        XCTAssertEqual(seconds("5:43:21"), (5 * 60 + 43) * 60 + 21)
        XCTAssertEqual(seconds("5:4:3"), (5 * 60 + 4) * 60 + 3)
        
        XCTAssertEqual(seconds("a"), nil)
        XCTAssertEqual(seconds("4:3:2:1"), nil)
    }

    func testFormat() {
        XCTAssertEqual(format(0), "0")
        XCTAssertEqual(format(1), "1")
        XCTAssertEqual(format(21), "21")
        XCTAssertEqual(format(321), "5:21")
        XCTAssertEqual(format(4321), "1:12:01")
        XCTAssertEqual(format(54321), "15:05:21")
        XCTAssertEqual(format(654321), "181:45:21")
        
        XCTAssertEqual(format(-1), nil)
    }
    
    func testFilename() {
        let path = #"[강제소환🏅#29] 1박2일 "선호"하는 사람들 다 모여라💓 김선호의 예능 뽀시래기적 모먼트 평생 못 잃어ㅣKBS 방송-otherVideo.webm"#
        print(#function, path.lengthOfBytes(using: .utf8))
    }
    
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
