#if canImport(XCTest)
import XCTest
@testable import Voibe

final class TextInjectorTests: XCTestCase {
    func testDeltaWhenPreviousIsPrefix() {
        let result = TextInjector.computeDelta(previousText: "hello", incomingText: "hello world")
        XCTAssertEqual(result.delta, " world")
        XCTAssertEqual(result.newPreviousText, "hello world")
    }

    func testDeltaWhenPreviousIsEmpty() {
        let result = TextInjector.computeDelta(previousText: "", incomingText: "hello")
        XCTAssertEqual(result.delta, "hello")
        XCTAssertEqual(result.newPreviousText, "hello")
    }

    func testDeltaWhenIncomingIsShorter() {
        let result = TextInjector.computeDelta(previousText: "hello world", incomingText: "hello")
        XCTAssertEqual(result.delta, "hello")
        XCTAssertEqual(result.newPreviousText, "hello")
    }

    func testDeltaWhenPreviousIsNotContained() {
        let result = TextInjector.computeDelta(previousText: "hello", incomingText: "goodbye")
        XCTAssertEqual(result.delta, "goodbye")
        XCTAssertEqual(result.newPreviousText, "goodbye")
    }

    func testDeltaWhenPreviousIsContainedButNotPrefix() {
        let result = TextInjector.computeDelta(previousText: "hello", incomingText: "say hello")
        XCTAssertEqual(result.delta, "say hello")
        XCTAssertEqual(result.newPreviousText, "say hello")
    }
}
#endif
