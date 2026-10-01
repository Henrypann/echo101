import Foundation

public enum EchoStoreError: Error, LocalizedError, Equatable {
    case invalidData(String)
    case notFound
    case confirmationRequired
    case unsafeFile
    case archiveTooLarge
    case unsupportedVersion
    case corruptArchive
    case restoreRequiresEmptyStore
    case recordingCleanupIncomplete
    case importRecoveryRequiresAttention

    public var errorDescription: String? {
        switch self {
        case .invalidData(let detail): return "Invalid data: \(detail)"
        case .notFound: return "The item no longer exists."
        case .confirmationRequired: return "Confirm the expression before using it."
        case .unsafeFile: return "The file is not a safe local recording."
        case .archiveTooLarge: return "The archive or recording exceeds the size limit."
        case .unsupportedVersion: return "This archive uses an unsupported version."
        case .corruptArchive: return "The archive is incomplete or damaged."
        case .restoreRequiresEmptyStore: return "Restore requires an empty library."
        case .recordingCleanupIncomplete: return "The library was updated, but some local recordings could not be removed. Restart the app to retry cleanup."
        case .importRecoveryRequiresAttention: return "An interrupted import could not be safely cleaned up. Unrecognized files were left unchanged. Review the local import files before trying again."
        }
    }
}

enum EchoValidation {
    static let schemaVersion = 2
    static let minimumSchemaVersion = 1
    static let maxUsageEvents = 2_000
    static let maxUsagePerExpression = 30
    static let maxArchiveBytes = 64 * 1_024 * 1_024
    static let maxClipBytes = 10 * 1_024 * 1_024
    static let maxTotalAudioBytes = 32 * 1_024 * 1_024
    static let allowedExtensions: Set<String> = ["m4a", "caf", "wav", "aiff", "mp3"]

    static func filename(_ value: String) throws {
        guard value.utf8.count <= 100,
              value == URL(fileURLWithPath: value).lastPathComponent,
              !value.contains("/"), !value.contains("\\"), !value.contains(".."),
              !value.contains("\0"),
              allowedExtensions.contains(URL(fileURLWithPath: value).pathExtension.lowercased()),
              UUID(uuidString: URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent) != nil
        else { throw EchoStoreError.unsafeFile }
    }

    static func snapshot(_ snapshot: EchoSnapshot) throws {
        let ids = snapshot.moments.map(\.id) + snapshot.expressions.map(\.id)
            + snapshot.clips.map(\.id) + snapshot.events.map(\.id)
            + snapshot.phrases.map(\.id) + snapshot.records.map(\.id) + snapshot.setupIssues.map(\.id)
        guard ids.count <= 100_000, Set(ids).count == ids.count else {
            throw EchoStoreError.invalidData("Duplicate identifiers or too many records.")
        }
        let moments = Set(snapshot.moments.map(\.id))
        let expressions = Dictionary(uniqueKeysWithValues: snapshot.expressions.map { ($0.id, $0) })
        let phrases = Set(snapshot.phrases.map(\.id))
        var filenames = Set<String>()
        for moment in snapshot.moments {
            try text(moment.scene, max: 160, required: true)
            try text(moment.note, max: 10_000)
            try date(moment.createdAt)
        }
        for expression in snapshot.expressions {
            guard moments.contains(expression.momentID) else { throw EchoStoreError.invalidData("Missing moment.") }
            try text(expression.text, max: 4_000, required: true)
            try text(expression.meaning, max: 4_000)
            try text(expression.spokenText, max: 4_000)
            if let parentTip = expression.parentTip { try text(parentTip, max: 1_000) }
            try text(expression.source, max: 100, required: true)
            guard expression.segments.count <= 100 else { throw EchoStoreError.invalidData("Too many segments.") }
            for segment in expression.segments { try text(segment, max: 4_000) }
            try date(expression.createdAt)
            if let lastUsedAt = expression.lastUsedAt { try date(lastUsedAt) }
        }
        for phrase in snapshot.phrases {
            try text(phrase.chinese, max: 4_000, required: true)
            try text(phrase.english, max: 4_000, required: true)
            try text(phrase.spokenEnglish, max: 4_000)
            try text(phrase.scene, max: 160, required: true)
            try text(phrase.source, max: 100, required: true)
            guard phrase.keywords.count <= 40 else { throw EchoStoreError.invalidData("Too many keywords.") }
            for keyword in phrase.keywords { try text(keyword, max: 200, required: true) }
            try date(phrase.createdAt)
        }
        for record in snapshot.records {
            try text(record.recognizedText, max: 4_000)
            try text(record.english, max: 4_000)
            try text(record.chineseMeaning, max: 4_000)
            if let phraseID = record.phraseID, !phrases.contains(phraseID) {
                throw EchoStoreError.invalidData("Missing phrase.")
            }
            if let name = record.grandparentAudio { try claim(name, filenames: &filenames) }
            if let name = record.childAudio { try claim(name, filenames: &filenames) }
            try date(record.createdAt)
        }
        for clip in snapshot.clips {
            guard expressions[clip.expressionID]?.isConfirmed == true else { throw EchoStoreError.invalidData("Recording has no confirmed expression.") }
            try claim(clip.filename, filenames: &filenames)
            try date(clip.createdAt)
        }
        for event in snapshot.events {
            guard expressions[event.expressionID]?.isConfirmed == true else { throw EchoStoreError.invalidData("Usage has no confirmed expression.") }
            try date(event.createdAt)
        }
        for issue in snapshot.setupIssues {
            try text(issue.code, max: 80, required: true)
            try text(issue.message, max: 500, required: true)
            try date(issue.createdAt)
        }
        if let consent = snapshot.consentGrantedAt { try date(consent) }
        if let exported = snapshot.lastExportAt { try date(exported) }
    }

    /// Usage history is capped so the 100,000-record guard cannot be reached by playback alone.
    static func cappedEvents(_ events: [UsageEvent]) -> [UsageEvent] {
        var kept: [UsageEvent] = []
        var perExpression: [UUID: Int] = [:]
        let newestFirst = events.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString > $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
        for event in newestFirst {
            if kept.count >= maxUsageEvents { break }
            let count = perExpression[event.expressionID, default: 0]
            if count >= maxUsagePerExpression { continue }
            perExpression[event.expressionID] = count + 1
            kept.append(event)
        }
        return kept
    }

    private static func claim(_ name: String, filenames: inout Set<String>) throws {
        try filename(name)
        guard filenames.insert(name.lowercased()).inserted else {
            throw EchoStoreError.invalidData("Duplicate recording filename.")
        }
    }

    static func text(_ value: String, max: Int, required: Bool = false) throws {
        guard value.count <= max, value.utf8.count <= max * 4, !value.contains("\0"),
              !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw EchoStoreError.invalidData("Text is empty, too long, or contains invalid characters.") }
    }

    static func date(_ value: Date) throws {
        guard value.timeIntervalSince1970.isFinite else { throw EchoStoreError.invalidData("Invalid date.") }
    }

    static func ordered(_ value: EchoSnapshot) -> EchoSnapshot {
        func newer<T>(_ a: T, _ b: T, date: (T) -> Date, id: (T) -> UUID) -> Bool {
            date(a) == date(b) ? id(a).uuidString < id(b).uuidString : date(a) > date(b)
        }
        return EchoSnapshot(
            moments: value.moments.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            expressions: value.expressions.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            clips: value.clips.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            events: value.events.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            phrases: value.phrases.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            records: value.records.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            consentGrantedAt: value.consentGrantedAt,
            allowCellular: value.allowCellular,
            lastExportAt: value.lastExportAt,
            setupIssues: value.setupIssues.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) })
    }
}
