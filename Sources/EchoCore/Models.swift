import Foundation

public struct Moment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var scene: String
    public var note: String
    public init(id: UUID = UUID(), createdAt: Date = Date(), scene: String, note: String) {
        self.id = id; self.createdAt = createdAt; self.scene = scene; self.note = note
    }
}

public struct Expression: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var momentID: UUID
    public var createdAt: Date
    public var text: String
    public var meaning: String
    public var spokenText: String
    public var segments: [String]
    public var isConfirmed: Bool
    public var isFavorite: Bool
    public var source: String
    public var lastUsedAt: Date?
    public var parentTip: String?
    public init(id: UUID = UUID(), momentID: UUID, createdAt: Date = Date(), text: String, meaning: String = "", spokenText: String = "", segments: [String] = [], isConfirmed: Bool = true, isFavorite: Bool = false, source: String = "manual", lastUsedAt: Date? = nil, parentTip: String? = nil) {
        self.id = id; self.momentID = momentID; self.createdAt = createdAt
        self.text = text; self.meaning = meaning; self.spokenText = spokenText; self.segments = segments
        self.isConfirmed = isConfirmed; self.isFavorite = isFavorite; self.source = source; self.lastUsedAt = lastUsedAt
        self.parentTip = parentTip
    }
    public var speechText: String { spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : spokenText }
}

public struct VoiceClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expressionID: UUID
    public var createdAt: Date
    public var filename: String
    public init(id: UUID = UUID(), expressionID: UUID, createdAt: Date = Date(), filename: String) {
        self.id = id; self.expressionID = expressionID; self.createdAt = createdAt; self.filename = filename
    }
}

public enum UsageKind: String, Codable, Sendable { case play, replay, favorite }
public struct UsageEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expressionID: UUID
    public var createdAt: Date
    public var kind: UsageKind
    public init(id: UUID = UUID(), expressionID: UUID, createdAt: Date = Date(), kind: UsageKind) {
        self.id = id; self.expressionID = expressionID; self.createdAt = createdAt; self.kind = kind
    }
}

public struct EchoSnapshot: Codable, Equatable, Sendable {
    public var moments: [Moment]
    public var expressions: [Expression]
    public var clips: [VoiceClip]
    public var events: [UsageEvent]
    public init(moments: [Moment] = [], expressions: [Expression] = [], clips: [VoiceClip] = [], events: [UsageEvent] = []) {
        self.moments = moments; self.expressions = expressions; self.clips = clips; self.events = events
    }
    public var isEmpty: Bool { moments.isEmpty && expressions.isEmpty && clips.isEmpty && events.isEmpty }
    public var confirmedExpressions: [Expression] {
        expressions.filter(\.isConfirmed).sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }
}
