#if canImport(XCTest)
import XCTest
@testable import Voibe

final class SSEStreamParserTests: XCTestCase {
    func testParsesSingleDeltaEvent() {
        var parser = SSEStreamParser()
        let data = "data: {\"type\":\"transcript.text.delta\",\"delta\":\"hello\"}\n\n".data(using: .utf8)!

        let events = parser.feed(data)

        XCTAssertEqual(events, [.delta("hello")])
    }

    func testParsesMultipleEventsIncludingDone() {
        var parser = SSEStreamParser()
        let data = """
        data: {"type":"transcript.text.delta","delta":"hi"}

        data: {"type":"transcript.text.delta","delta":" there"}

        data: {"type":"transcript.text.done","text":"hi there"}

        """.data(using: .utf8)!

        let events = parser.feed(data)

        XCTAssertEqual(events, [.delta("hi"), .delta(" there"), .done("hi there")])
    }

    func testParsesDoneSentinel() {
        var parser = SSEStreamParser()
        let data = "data: [DONE]\n\n".data(using: .utf8)!

        let events = parser.feed(data)

        XCTAssertEqual(events, [.done(nil)])
    }

    func testParsesCRLFDelimiters() {
        var parser = SSEStreamParser()
        let data = "data: {\"type\":\"transcript.text.delta\",\"delta\":\"hi\"}\r\n\r\n".data(using: .utf8)!

        let events = parser.feed(data)

        XCTAssertEqual(events, [.delta("hi")])
    }

    func testFlushesTrailingEventWithoutDelimiter() {
        var parser = SSEStreamParser()
        let data = "data: {\"type\":\"transcript.text.delta\",\"delta\":\"trail\"}\n".data(using: .utf8)!

        XCTAssertEqual(parser.feed(data), [])
        XCTAssertEqual(parser.flush(), [.delta("trail")])
    }

    func testIgnoresInvalidJSON() {
        var parser = SSEStreamParser()
        let data = "data: not-json\n\n".data(using: .utf8)!

        let events = parser.feed(data)

        XCTAssertEqual(events, [])
    }

    func testHandlesPartialFramesAcrossFeeds() {
        var parser = SSEStreamParser()
        let part1 = "data: {\"type\":\"transcript.text.delta\",\"delta\":\"hel".data(using: .utf8)!
        let part2 = "lo\"}\n\n".data(using: .utf8)!

        XCTAssertEqual(parser.feed(part1), [])
        XCTAssertEqual(parser.feed(part2), [.delta("hello")])
    }
}
#endif
