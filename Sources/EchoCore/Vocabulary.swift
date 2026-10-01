import Foundation

public struct VocabularyWord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var english: String
    public var chinese: String
    public var emoji: String
    public var exampleEn: String
    public var exampleZh: String
    public var ipa: String
    public init(id: String, english: String, chinese: String, emoji: String = "", exampleEn: String, exampleZh: String, ipa: String = "") {
        self.id = id; self.english = english; self.chinese = chinese; self.emoji = emoji
        self.exampleEn = exampleEn; self.exampleZh = exampleZh; self.ipa = ipa
    }
}

public struct VocabularyCategory: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var chinese: String
    public var english: String
    public var emoji: String
    public var subtitle: String
    public var pinned: Bool
    public var words: [VocabularyWord]
    public init(id: String, chinese: String, english: String, emoji: String = "", subtitle: String = "", pinned: Bool = false, words: [VocabularyWord]) {
        self.id = id; self.chinese = chinese; self.english = english; self.emoji = emoji
        self.subtitle = subtitle; self.pinned = pinned; self.words = words
    }
}

public struct VocabularyCatalog: Codable, Equatable, Sendable {
    public var categories: [VocabularyCategory]
    public init(categories: [VocabularyCategory]) { self.categories = categories }

    public static func load(from data: Data) throws -> VocabularyCatalog {
        let decoded = try JSONDecoder().decode(VocabularyCatalog.self, from: data)
        return VocabularyCatalog(categories: ordered(decoded.categories))
    }

    public static func load() throws -> VocabularyCatalog {
        guard let url = Bundle.module.url(forResource: "Vocabulary", withExtension: "json") else {
            throw EchoStoreError.invalidData("Missing vocabulary file.")
        }
        return try load(from: Data(contentsOf: url))
    }

    /// Pinned category stays first. Every other category keeps the file order.
    static func ordered(_ categories: [VocabularyCategory]) -> [VocabularyCategory] {
        let pinned = categories.filter(\.pinned)
        let rest = categories.filter { !$0.pinned }
        return pinned + rest
    }
}
