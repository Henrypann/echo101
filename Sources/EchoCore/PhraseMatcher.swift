import Foundation

public struct PhraseMatch: Equatable, Sendable {
    public var phrase: LibraryPhrase
    public var score: Double
}

public enum MatchPlan: Equatable, Sendable {
    case library(LibraryPhrase)
    case askModel
    case saveForParent
}

/// Chinese normalization and keyword scoring. Library matches win; the model is only a fallback.
public enum PhraseMatcher {
    public static let threshold = 0.80

    public static func normalize(_ raw: String) -> String {
        let folded = raw.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars: [Unicode.Scalar] = []
        for scalar in folded.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            if CharacterSet.punctuationCharacters.contains(scalar) { continue }
            if CharacterSet.symbols.contains(scalar) { continue }
            let value = scalar.value
            // Ideographic punctuation and fullwidth space that CharacterSet can miss.
            if (0x3000...0x303F).contains(value) || value == 0xFF0C || value == 0xFF01 || value == 0xFF1F || value == 0xFF1A || value == 0xFF1B { continue }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    public static func bestMatch(utterance: String, library: [LibraryPhrase]) -> PhraseMatch? {
        let spoken = normalize(utterance)
        guard spoken.count >= 1 else { return nil }
        var best: PhraseMatch?
        for phrase in library {
            let score = score(spoken: spoken, phrase: phrase)
            if score >= threshold, best == nil || score > best!.score {
                best = PhraseMatch(phrase: phrase, score: score)
            }
        }
        return best
    }

    /// A good library match never asks the model. Without consent or a network path, save the line for parents.
    public static func plan(utterance: String, library: [LibraryPhrase], modelAllowed: Bool) -> MatchPlan {
        if let match = bestMatch(utterance: utterance, library: library) {
            return .library(match.phrase)
        }
        return modelAllowed ? .askModel : .saveForParent
    }

    public static func matchedRecord(utterance: String, phrase: LibraryPhrase, at date: Date = Date()) -> SpeechRecord {
        SpeechRecord(createdAt: date, recognizedText: utterance, english: phrase.english, chinese: phrase.chinese, phraseID: phrase.id, origin: "library", needsConfirmation: false, scene: phrase.scene)
    }

    public static func generatedRecord(utterance: String, english: String, chinese: String, at date: Date = Date()) -> SpeechRecord {
        SpeechRecord(createdAt: date, recognizedText: utterance, english: english, chinese: chinese, phraseID: nil, origin: "model", needsConfirmation: true, scene: "日常")
    }

    public static func pendingRecord(utterance: String, at date: Date = Date()) -> SpeechRecord {
        SpeechRecord(createdAt: date, recognizedText: utterance, english: "", chinese: "", phraseID: nil, origin: "pending", needsConfirmation: true, scene: "日常")
    }

    private static func score(spoken: String, phrase: LibraryPhrase) -> Double {
        let probes = [phrase.chinese] + phrase.keywords
        var best = 0.0
        for probe in probes {
            let target = normalize(probe)
            guard target.count >= 2 else { continue }
            if spoken == target { return 1 }
            if spoken.contains(target) || (target.contains(spoken) && spoken.count >= 2) {
                let shorter = Double(min(spoken.count, target.count))
                let longer = Double(max(spoken.count, target.count))
                let coverage = shorter / longer
                if spoken.contains(target) {
                    best = max(best, coverage >= 0.45 ? 0.86 + 0.14 * coverage : 0.84)
                } else if coverage >= 0.6 {
                    best = max(best, 0.82 + 0.16 * coverage)
                }
            }
            best = max(best, dice(spoken, target))
        }
        return best
    }

    private static func dice(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let left = bigrams(a)
        let right = bigrams(b)
        if left.isEmpty || right.isEmpty { return 0 }
        var overlap = 0
        for (gram, count) in left {
            if let other = right[gram] { overlap += min(count, other) }
        }
        let total = left.values.reduce(0, +) + right.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return (2.0 * Double(overlap)) / Double(total)
    }

    private static func bigrams(_ text: String) -> [String: Int] {
        let chars = Array(text)
        guard chars.count >= 2 else { return [:] }
        var map: [String: Int] = [:]
        for index in 0..<(chars.count - 1) {
            let gram = String(chars[index]) + String(chars[index + 1])
            map[gram, default: 0] += 1
        }
        return map
    }
}
