import Foundation

public struct ImageCredit: Codable, Equatable, Sendable {
    public var author: String
    public var license: String
    public var licenseURL: String
    public var sourceURL: String
    public init(author: String, license: String, licenseURL: String, sourceURL: String) {
        self.author = author
        self.license = license
        self.licenseURL = licenseURL
        self.sourceURL = sourceURL
    }
}

public struct VocabularyWord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var english: String
    public var chinese: String
    public var emoji: String
    public var exampleEn: String
    public var exampleZh: String
    public var ipa: String
    /// Bundled picture name, without a file extension. Empty when the row should show `emoji` instead.
    public var image: String
    public var credit: ImageCredit?
    public init(id: String, english: String, chinese: String, emoji: String = "", exampleEn: String, exampleZh: String, ipa: String = "", image: String = "", credit: ImageCredit? = nil) {
        self.id = id; self.english = english; self.chinese = chinese; self.emoji = emoji
        self.exampleEn = exampleEn; self.exampleZh = exampleZh; self.ipa = ipa
        self.image = image; self.credit = credit
    }
}

public struct VocabularyCategory: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var chinese: String
    public var english: String
    public var emoji: String
    public var image: String
    public var subtitle: String
    public var pinned: Bool
    public var words: [VocabularyWord]
    public init(id: String, chinese: String, english: String, emoji: String = "", subtitle: String = "", pinned: Bool = false, image: String = "", words: [VocabularyWord]) {
        self.id = id; self.chinese = chinese; self.english = english; self.emoji = emoji
        self.subtitle = subtitle; self.pinned = pinned; self.image = image; self.words = words
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

public enum VocabularyImages {
    public static let openMojiAttribution = "All emojis designed by OpenMoji – the open-source emoji and icon project. License: CC BY-SA 4.0"
    public static let openMojiProjectURL = URL(string: "https://openmoji.org")!
    public static let openMojiLicenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!

    /// Locates a bundled PNG or JPEG for a vocabulary `image` name.
    public static func resourceURL(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\") else { return nil }
        for ext in ["png", "jpg", "jpeg"] {
            if let url = Bundle.module.url(forResource: trimmed, withExtension: ext) { return url }
            if let url = Bundle.module.url(forResource: trimmed, withExtension: ext, subdirectory: "Pictures") { return url }
        }
        return nil
    }
}
