import XCTest
@testable import LumaAI

final class SSEParserTests: XCTestCase {

    var parser: SSEParser!

    override func setUp() {
        super.setUp()
        parser = SSEParser()
    }

    func testTokenEventParsing() throws {
        let chunk = "event: token\ndata: {\"text\": \"Hello, \"}\n\n"
        let events = parser.feed(chunk)

        XCTAssertEqual(events.count, 1)
        if case .token(let text) = events[0] {
            XCTAssertEqual(text, "Hello, ")
        } else {
            XCTFail("Expected .token event")
        }
    }

    func testMultipleTokensParsing() throws {
        let chunk = "event: token\ndata: {\"text\": \"Hello\"}\n\nevent: token\ndata: {\"text\": \" world\"}\n\nevent: done\ndata: {}\n\n"
        let events = parser.feed(chunk)

        XCTAssertEqual(events.count, 3)

        if case .token(let t1) = events[0] {
            XCTAssertEqual(t1, "Hello")
        } else {
            XCTFail("Expected token")
        }

        if case .token(let t2) = events[1] {
            XCTAssertEqual(t2, " world")
        } else {
            XCTFail("Expected token")
        }

        if case .done = events[2] {
            // Success
        } else {
            XCTFail("Expected done event")
        }
    }

    func testPartialChunkBuffering() throws {
        let part1 = "event: to"
        let events1 = parser.feed(part1)
        XCTAssertTrue(events1.isEmpty)

        let part2 = "ken\ndata: {\"text\": \"Streamed data\"}\n\n"
        let events2 = parser.feed(part2)
        XCTAssertEqual(events2.count, 1)

        if case .token(let text) = events2[0] {
            XCTAssertEqual(text, "Streamed data")
        } else {
            XCTFail("Expected token event after completing buffer")
        }
    }

    func testImageEventParsing() throws {
        let raw = "event: image\ndata: {\"id\":\"img_abc\",\"prompt\":\"Sunset on Mars\",\"aspect_ratio\":\"1:1\",\"image_url\":\"/api/image/view/img_abc\",\"width\":1024,\"height\":1024,\"provider\":\"FLUX\",\"model\":\"flux\"}\n\n"
        let events = parser.feed(raw)

        XCTAssertEqual(events.count, 1)
        if case .image(let attachment) = events[0] {
            XCTAssertEqual(attachment.id, "img_abc")
            XCTAssertEqual(attachment.prompt, "Sunset on Mars")
            XCTAssertEqual(attachment.aspectRatio, "1:1")
            XCTAssertEqual(attachment.imageUrl, "/api/image/view/img_abc")
            XCTAssertEqual(attachment.width, 1024)
            XCTAssertEqual(attachment.height, 1024)
        } else {
            XCTFail("Expected image attachment event")
        }
    }

    func testErrorEventParsing() throws {
        let raw = "event: error\ndata: {\"message\": \"Model rate limit reached\"}\n\n"
        let events = parser.feed(raw)

        XCTAssertEqual(events.count, 1)
        if case .error(let msg) = events[0] {
            XCTAssertEqual(msg, "Model rate limit reached")
        } else {
            XCTFail("Expected error event")
        }
    }

    func testCRLFLineEndingsParsing() throws {
        let chunk = "event: token\r\ndata: {\"text\": \"Hello with CRLF\"}\r\n\r\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        if case .token(let text) = events[0] {
            XCTAssertEqual(text, "Hello with CRLF")
        } else {
            XCTFail("Expected token event with CRLF")
        }
    }
}
