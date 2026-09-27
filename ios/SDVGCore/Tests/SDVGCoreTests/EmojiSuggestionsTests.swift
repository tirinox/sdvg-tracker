import Foundation
import XCTest

@testable import SDVGCore

/// Answers /api/suggest-emoji with a fixed body and remembers the requests.
private final class FakeEmojiServer: @unchecked Sendable {
    var status = 200
    var body = #"{"suggestions": [{"emoji": "🦷", "score": 0.96}, {"emoji": "🩺", "score": 0.88}], "pick": "🦷"}"#
    var offline = false
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    var transport: HTTPTransport {
        { [self] request in
            try lock.withLock {
                requests.append(request)
                if offline { throw URLError(.notConnectedToInternet) }
                return (Data(body.utf8), status)
            }
        }
    }
}

final class EmojiSuggestionsTests: XCTestCase {
    let config = SyncConfig(baseURL: "https://sdvg.test", token: "tok")

    func testAsksTheServerWithTheTitleInTheBody() async throws {
        let server = FakeEmojiServer()
        let s = await EmojiSuggestions.fetch("  Записаться к стоматологу ", config: config, transport: server.transport)
        XCTAssertEqual(s, EmojiSuggestions(emoji: ["🦷", "🩺"], pick: "🦷"))
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sdvg.test/api/suggest-emoji")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["text"] as? String, "Записаться к стоматологу")
        XCTAssertEqual(body?["limit"] as? Int, 5)
    }

    func testStaysQuietWithoutAServerOrATitle() async {
        let server = FakeEmojiServer()
        let noServer = await EmojiSuggestions.fetch("Стоматолог", config: nil, transport: server.transport)
        let noTitle = await EmojiSuggestions.fetch("   ", config: config, transport: server.transport)
        XCTAssertEqual(noServer, .none)
        XCTAssertEqual(noTitle, .none)
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testLoadingModelOrNoNetworkIsNoSuggestions() async {
        let server = FakeEmojiServer()
        server.status = 503
        server.body = #"{"detail": {"error": "emoji_loading"}}"#
        let loading = await EmojiSuggestions.fetch("Стоматолог", config: config, transport: server.transport)
        server.offline = true
        let offline = await EmojiSuggestions.fetch("Стоматолог", config: config, transport: server.transport)
        XCTAssertEqual(loading, .none)
        XCTAssertEqual(offline, .none)
    }

    func testUnsureModelHasNoPick() async {
        let server = FakeEmojiServer()
        server.body = #"{"suggestions": [{"emoji": "🛏️", "score": 0.86}], "pick": null}"#
        let s = await EmojiSuggestions.fetch("Кружки клеить на стулья", config: config, transport: server.transport)
        XCTAssertEqual(s, EmojiSuggestions(emoji: ["🛏️"], pick: nil))
    }

    func testPickGoesOnlyToATaskWithoutAnEmoji() throws {
        let store = try Store.open(path: nil)
        let bare = try store.createTask(TaskDraft(title: "Выгулять собаку"))
        var chosen = TaskDraft(title: "Выгулять собаку")
        chosen.emoji = "🦮"
        let withEmoji = try store.createTask(chosen)

        try store.applyEmojiPick("🐕", toTask: bare)
        try store.applyEmojiPick("🐕", toTask: withEmoji)

        XCTAssertEqual(try store.get(.task, bare).map(TaskRecord.init)?.emoji, "🐕")
        XCTAssertEqual(try store.get(.task, withEmoji).map(TaskRecord.init)?.emoji, "🦮")
    }
}
