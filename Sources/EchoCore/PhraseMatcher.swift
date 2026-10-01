import Foundation

public struct PhraseMatch: Equatable, Sendable {
    public var phrase: LibraryPhrase
    public var score: Double
    public init(phrase: LibraryPhrase, score: Double) {
        self.phrase = phrase
        self.score = score
    }
}

public enum UtterancePlan: Equatable, Sendable {
    case unheard
    case library(LibraryPhrase)
    case callModel
    case savePending
}

/// Library-first matching. A generated sentence is never returned from here.
public enum PhraseMatcher {
    public static let acceptScore = 0.72

    public static func normalize(_ text: String) -> String {
        let dropped = CharacterSet.punctuationCharacters
            .union(.whitespacesAndNewlines)
            .union(.symbols)
            .union(.controlCharacters)
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars.filter { !dropped.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    public static func bestMatch(utterance: String, phrases: [LibraryPhrase]) -> PhraseMatch? {
        let norm = normalize(utterance)
        guard norm.count >= 1 else { return nil }
        var best: PhraseMatch?
        for phrase in phrases {
            let score = similarity(utterance: norm, phrase: phrase)
            guard score >= acceptScore else { continue }
            if best == nil || score > best!.score {
                best = PhraseMatch(phrase: phrase, score: score)
            }
        }
        return best
    }

    static func similarity(utterance norm: String, phrase: LibraryPhrase) -> Double {
        let candidates = [phrase.chinese] + phrase.keywords
        var best = 0.0
        for raw in candidates {
            let target = normalize(raw)
            guard target.count >= 1 else { continue }
            if target == norm { return 1 }
            if target.count >= 2, norm.count >= 2, (norm.contains(target) || target.contains(norm)) {
                let cover = Double(min(norm.count, target.count)) / Double(max(norm.count, target.count))
                best = max(best, 0.78 + 0.2 * cover)
            }
            best = max(best, bigramJaccard(norm, target))
        }
        return best
    }

    private static func bigramJaccard(_ a: String, _ b: String) -> Double {
        let left = bigrams(a)
        let right = bigrams(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 2 else { return chars.isEmpty ? [] : [String(chars[0])] }
        var result: Set<String> = []
        for index in 0..<(chars.count - 1) {
            result.insert(String(chars[index...index + 1]))
        }
        return result
    }
}

public enum UtterancePlanner {
    /// Match the local library first. Call the model only when nothing is close enough,
    /// consent was granted, and a key plus network are ready. Otherwise save a pending record.
    public static func plan(text: String, phrases: [LibraryPhrase], consent: Bool, modelReady: Bool) -> UtterancePlan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unheard }
        if let match = PhraseMatcher.bestMatch(utterance: trimmed, phrases: phrases) {
            return .library(match.phrase)
        }
        if consent && modelReady { return .callModel }
        return .savePending
    }
}
