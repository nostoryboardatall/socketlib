import XCTest
@testable import StompClientLib

final class StompClientLibTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(StompClientLib().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
