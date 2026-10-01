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

public struct LibraryPhrase: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var chinese: String
    public var english: String
    public var spokenEnglish: String
    public var scene: String
    public var keywords: [String]
    public var source: String
    public init(id: UUID = UUID(), createdAt: Date = Date(), chinese: String, english: String, spokenEnglish: String = "", scene: String = "Everyday", keywords: [String] = [], source: String = "parent") {
        self.id = id; self.createdAt = createdAt; self.chinese = chinese; self.english = english
        self.spokenEnglish = spokenEnglish; self.scene = scene; self.keywords = keywords; self.source = source
    }
    public var speechText: String { spokenEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? english : spokenEnglish }
}

public enum SpokenKind: String, Codable, Sendable {
    case library
    case pendingParent
    case confirmed
}

public struct SpokenRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var recognizedText: String
    public var english: String
    public var chineseMeaning: String
    public var phraseID: UUID?
    public var kind: SpokenKind
    public var grandparentAudio: String?
    public var childAudio: String?
    public init(id: UUID = UUID(), createdAt: Date = Date(), recognizedText: String, english: String = "", chineseMeaning: String = "", phraseID: UUID? = nil, kind: SpokenKind = .pendingParent, grandparentAudio: String? = nil, childAudio: String? = nil) {
        self.id = id; self.createdAt = createdAt; self.recognizedText = recognizedText
        self.english = english; self.chineseMeaning = chineseMeaning; self.phraseID = phraseID
        self.kind = kind; self.grandparentAudio = grandparentAudio; self.childAudio = childAudio
    }
    public var waitsForParent: Bool { kind == .pendingParent }
}

public struct SetupIssue: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var code: String
    public var message: String
    public init(id: UUID = UUID(), createdAt: Date = Date(), code: String, message: String) {
        self.id = id; self.createdAt = createdAt; self.code = code; self.message = message
    }
}

public struct EchoSnapshot: Codable, Equatable, Sendable {
    public var moments: [Moment]
    public var expressions: [Expression]
    public var clips: [VoiceClip]
    public var events: [UsageEvent]
    public var phrases: [LibraryPhrase]
    public var records: [SpokenRecord]
    public var consentGrantedAt: Date?
    public var allowCellular: Bool
    public var lastExportAt: Date?
    public var setupIssues: [SetupIssue]

    public init(moments: [Moment] = [], expressions: [Expression] = [], clips: [VoiceClip] = [], events: [UsageEvent] = [], phrases: [LibraryPhrase] = [], records: [SpokenRecord] = [], consentGrantedAt: Date? = nil, allowCellular: Bool = false, lastExportAt: Date? = nil, setupIssues: [SetupIssue] = []) {
        self.moments = moments; self.expressions = expressions; self.clips = clips; self.events = events
        self.phrases = phrases; self.records = records; self.consentGrantedAt = consentGrantedAt
        self.allowCellular = allowCellular; self.lastExportAt = lastExportAt; self.setupIssues = setupIssues
    }

    public var isEmpty: Bool {
        moments.isEmpty && expressions.isEmpty && clips.isEmpty && events.isEmpty
            && phrases.isEmpty && records.isEmpty && setupIssues.isEmpty
    }

    /// Restore stays blocked once a family has real content. Seed phrases alone do not block it.
    public var blocksRestore: Bool {
        !moments.isEmpty || !expressions.isEmpty || !clips.isEmpty || !events.isEmpty || !records.isEmpty
            || phrases.contains { $0.source != "seed" } || !setupIssues.isEmpty
    }

    public var confirmedExpressions: [Expression] {
        expressions.filter(\.isConfirmed).sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    public var referencedAudioFilenames: [String] {
        clips.map(\.filename) + records.flatMap { [$0.grandparentAudio, $0.childAudio].compactMap { $0 } }
    }

    public var exportIsOverdue: Bool {
        guard let lastExportAt else { return true }
        return Date().timeIntervalSince(lastExportAt) > 7 * 24 * 60 * 60
    }

    enum CodingKeys: String, CodingKey {
        case moments, expressions, clips, events, phrases, records
        case consentGrantedAt, allowCellular, lastExportAt, setupIssues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moments = try container.decodeIfPresent([Moment].self, forKey: .moments) ?? []
        expressions = try container.decodeIfPresent([Expression].self, forKey: .expressions) ?? []
        clips = try container.decodeIfPresent([VoiceClip].self, forKey: .clips) ?? []
        events = try container.decodeIfPresent([UsageEvent].self, forKey: .events) ?? []
        phrases = try container.decodeIfPresent([LibraryPhrase].self, forKey: .phrases) ?? []
        records = try container.decodeIfPresent([SpokenRecord].self, forKey: .records) ?? []
        consentGrantedAt = try container.decodeIfPresent(Date.self, forKey: .consentGrantedAt)
        allowCellular = try container.decodeIfPresent(Bool.self, forKey: .allowCellular) ?? false
        lastExportAt = try container.decodeIfPresent(Date.self, forKey: .lastExportAt)
        setupIssues = try container.decodeIfPresent([SetupIssue].self, forKey: .setupIssues) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moments, forKey: .moments)
        try container.encode(expressions, forKey: .expressions)
        try container.encode(clips, forKey: .clips)
        try container.encode(events, forKey: .events)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(records, forKey: .records)
        try container.encodeIfPresent(consentGrantedAt, forKey: .consentGrantedAt)
        try container.encode(allowCellular, forKey: .allowCellular)
        try container.encodeIfPresent(lastExportAt, forKey: .lastExportAt)
        try container.encode(setupIssues, forKey: .setupIssues)
    }
}
