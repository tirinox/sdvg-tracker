import Foundation

/// Emoji the server suggests for a title: POST /api/suggest-emoji.
public struct EmojiSuggestions: Equatable, Sendable {
    /// Best first.
    public var emoji: [String]
    /// The emoji to set without asking, or nil: the server's model is not sure enough.
    public var pick: String?

    public static let none = EmojiSuggestions(emoji: [], pick: nil)

    public init(emoji: [String], pick: String?) {
        self.emoji = emoji
        self.pick = pick
    }

    private struct Body: Encodable {
        let text: String
        let limit: Int
    }

    private struct Answer: Decodable {
        struct Suggestion: Decodable { let emoji: String }
        let suggestions: [Suggestion]
        let pick: String?
    }

    /// Nothing on any failure: no server configured, offline, the model still loading.
    /// Suggestions are a nicety, so there is no retry and no error state.
    public static func fetch(
        _ text: String, config: SyncConfig?, limit: Int = 5, transport: HTTPTransport = urlSessionTransport
    ) async -> EmojiSuggestions {
        // The server counts code points, not grapheme clusters.
        let title = String(String.UnicodeScalarView(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(500)))
        guard !title.isEmpty, let config, let url = URL(string: config.baseURL + "/api/suggest-emoji") else { return .none }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(Body(text: title, limit: limit))
        guard let (data, code) = try? await transport(request), code == 200,
              let answer = try? JSONDecoder().decode(Answer.self, from: data)
        else { return .none }
        return EmojiSuggestions(emoji: answer.suggestions.map(\.emoji), pick: answer.pick)
    }
}

extension Store {
    /// The server's pick for a task created without an emoji, unless one was set meanwhile
    /// (here or, after a sync, on another device).
    public func applyEmojiPick(_ emoji: String, toTask id: String) throws {
        guard let task = try get(.task, id).map(TaskRecord.init), task.emoji == nil else { return }
        try updateTask(id, ["emoji": .string(emoji)])
    }
}
