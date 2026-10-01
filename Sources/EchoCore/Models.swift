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

public struct VoiceClip: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expressionID: UUID?
    public var createdAt: Date
    public var filename: String
    public var recordID: UUID?
    public var role: String
    public init(id: UUID = UUID(), expressionID: UUID? = nil, createdAt: Date = Date(), filename: String, recordID: UUID? = nil, role: String = "expression") {
        self.id = id
        self.expressionID = expressionID
        self.createdAt = createdAt
        self.filename = filename
        self.recordID = recordID
        self.role = role
    }

    private enum CodingKeys: String, CodingKey { case id, expressionID, createdAt, filename, recordID, role }
}

extension VoiceClip: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        expressionID = try container.decodeIfPresent(UUID.self, forKey: .expressionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        filename = try container.decode(String.self, forKey: .filename)
        recordID = try container.decodeIfPresent(UUID.self, forKey: .recordID)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? (recordID == nil ? "expression" : "grandparent")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(expressionID, forKey: .expressionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(filename, forKey: .filename)
        try container.encodeIfPresent(recordID, forKey: .recordID)
        try container.encode(role, forKey: .role)
    }
}

public enum UsageKind: String, Codable, Sendable { case play, replay, favorite }

public struct UsageEvent: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expressionID: UUID
    public var createdAt: Date
    public var kind: UsageKind
    public var count: Int
    public init(id: UUID = UUID(), expressionID: UUID, createdAt: Date = Date(), kind: UsageKind, count: Int = 1) {
        self.id = id
        self.expressionID = expressionID
        self.createdAt = createdAt
        self.kind = kind
        self.count = count
    }

    private enum CodingKeys: String, CodingKey { case id, expressionID, createdAt, kind, count }
}

extension UsageEvent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        expressionID = try container.decode(UUID.self, forKey: .expressionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decode(UsageKind.self, forKey: .kind)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(expressionID, forKey: .expressionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(kind, forKey: .kind)
        try container.encode(count, forKey: .count)
    }
}

/// A parent-confirmed sentence. Generated text stays out of this list until a parent confirms it.
public struct LibraryPhrase: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var english: String
    public var chinese: String
    public var scene: String
    public var keywords: [String]
    public var source: String
    public var lastUsedAt: Date?
    public init(id: UUID = UUID(), createdAt: Date = Date(), english: String, chinese: String, scene: String = "日常", keywords: [String] = [], source: String = "parent", lastUsedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.english = english
        self.chinese = chinese
        self.scene = scene
        self.keywords = keywords
        self.source = source
        self.lastUsedAt = lastUsedAt
    }
}

/// One grandparent utterance, plus the English that was played or left for parents to fill in.
public struct SpeechRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var recognizedText: String
    public var english: String
    public var chinese: String
    public var phraseID: UUID?
    /// `library` (matched or later confirmed), `model`, `pending`, or `archived`.
    public var origin: String
    public var needsConfirmation: Bool
    public var scene: String
    public init(id: UUID = UUID(), createdAt: Date = Date(), recognizedText: String, english: String = "", chinese: String = "", phraseID: UUID? = nil, origin: String, needsConfirmation: Bool, scene: String = "日常") {
        self.id = id
        self.createdAt = createdAt
        self.recognizedText = recognizedText
        self.english = english
        self.chinese = chinese
        self.phraseID = phraseID
        self.origin = origin
        self.needsConfirmation = needsConfirmation
        self.scene = scene
    }
}

public struct EchoSettings: Codable, Equatable, Sendable {
    public var consentGranted: Bool
    public var allowCellular: Bool
    public var lastExportAt: Date?
    public init(consentGranted: Bool = false, allowCellular: Bool = false, lastExportAt: Date? = nil) {
        self.consentGranted = consentGranted
        self.allowCellular = allowCellular
        self.lastExportAt = lastExportAt
    }
}

public struct EchoSnapshot: Equatable, Sendable {
    public var moments: [Moment]
    public var expressions: [Expression]
    public var clips: [VoiceClip]
    public var events: [UsageEvent]
    public var library: [LibraryPhrase]
    public var records: [SpeechRecord]
    public var settings: EchoSettings
    public init(moments: [Moment] = [], expressions: [Expression] = [], clips: [VoiceClip] = [], events: [UsageEvent] = [], library: [LibraryPhrase] = [], records: [SpeechRecord] = [], settings: EchoSettings = EchoSettings()) {
        self.moments = moments
        self.expressions = expressions
        self.clips = clips
        self.events = events
        self.library = library
        self.records = records
        self.settings = settings
    }
    public var isEmpty: Bool {
        moments.isEmpty && expressions.isEmpty && clips.isEmpty && events.isEmpty && library.isEmpty && records.isEmpty
    }
    /// Fresh install of the built-in phrases only. Restore may replace this; anything a parent added may not.
    public var isPristineSeededLibrary: Bool {
        records.isEmpty && moments.isEmpty && expressions.isEmpty && clips.isEmpty && events.isEmpty
            && !library.isEmpty && library.allSatisfy { $0.source == "seed" }
    }
    public var confirmedExpressions: [Expression] {
        expressions.filter(\.isConfirmed).sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }
    /// Daily rotation is the confirmed library only. Unconfirmed model lines are never included.
    public var rotationPhrases: [LibraryPhrase] {
        library.sorted { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }
    }
    public var pendingRecords: [SpeechRecord] {
        records.filter(\.needsConfirmation).sorted { $0.createdAt > $1.createdAt }
    }

    private enum CodingKeys: String, CodingKey {
        case moments, expressions, clips, events, library, records, settings
    }
}

extension EchoSnapshot: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moments = try container.decodeIfPresent([Moment].self, forKey: .moments) ?? []
        expressions = try container.decodeIfPresent([Expression].self, forKey: .expressions) ?? []
        clips = try container.decodeIfPresent([VoiceClip].self, forKey: .clips) ?? []
        events = try container.decodeIfPresent([UsageEvent].self, forKey: .events) ?? []
        library = try container.decodeIfPresent([LibraryPhrase].self, forKey: .library) ?? []
        records = try container.decodeIfPresent([SpeechRecord].self, forKey: .records) ?? []
        settings = try container.decodeIfPresent(EchoSettings.self, forKey: .settings) ?? EchoSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moments, forKey: .moments)
        try container.encode(expressions, forKey: .expressions)
        try container.encode(clips, forKey: .clips)
        try container.encode(events, forKey: .events)
        try container.encode(library, forKey: .library)
        try container.encode(records, forKey: .records)
        try container.encode(settings, forKey: .settings)
    }
}

struct EchoSnapshotV1: Codable, Equatable, Sendable {
    var moments: [Moment]
    var expressions: [Expression]
    var clips: [VoiceClip]
    var events: [UsageEvent]
}
