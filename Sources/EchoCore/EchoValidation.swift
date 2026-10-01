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
    /// Current on-disk schema. Version 1 snapshots are migrated; newer versions are rejected.
    static let schemaVersion = 2
    static let minimumSchemaVersion = 1
    static let maxEventsPerTarget = 24
    static let eventWriteBudget = 90_000
    static let maxArchiveBytes = 64 * 1_024 * 1_024
    static let maxClipBytes = 10 * 1_024 * 1_024
    static let maxTotalAudioBytes = 32 * 1_024 * 1_024
    static let allowedExtensions: Set<String> = ["m4a", "caf", "wav", "aiff", "mp3"]
    static let recordOrigins: Set<String> = ["library", "model", "pending", "archived"]
    static let clipRoles: Set<String> = ["expression", "grandparent", "child"]

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
            + snapshot.library.map(\.id) + snapshot.records.map(\.id)
        guard ids.count <= 100_000, Set(ids).count == ids.count else {
            throw EchoStoreError.invalidData("Duplicate identifiers or too many records.")
        }
        let moments = Set(snapshot.moments.map(\.id))
        let expressions = Dictionary(uniqueKeysWithValues: snapshot.expressions.map { ($0.id, $0) })
        let libraryIDs = Set(snapshot.library.map(\.id))
        let recordIDs = Set(snapshot.records.map(\.id))
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
        for phrase in snapshot.library {
            try text(phrase.english, max: 4_000, required: true)
            try text(phrase.chinese, max: 4_000, required: true)
            try text(phrase.scene, max: 160, required: true)
            try text(phrase.source, max: 100, required: true)
            guard phrase.keywords.count <= 20 else { throw EchoStoreError.invalidData("Too many keywords.") }
            for keyword in phrase.keywords { try text(keyword, max: 80) }
            try date(phrase.createdAt)
            if let lastUsedAt = phrase.lastUsedAt { try date(lastUsedAt) }
        }
        for record in snapshot.records {
            guard recordOrigins.contains(record.origin) else { throw EchoStoreError.invalidData("Unknown record origin.") }
            try text(record.recognizedText, max: 4_000, required: true)
            try text(record.scene, max: 160, required: true)
            try date(record.createdAt)
            switch record.origin {
            case "library":
                guard !record.needsConfirmation, let phraseID = record.phraseID, libraryIDs.contains(phraseID) else {
                    throw EchoStoreError.invalidData("Library record is not linked to a confirmed phrase.")
                }
                try text(record.english, max: 4_000, required: true)
                try text(record.chinese, max: 4_000, required: true)
            case "model":
                guard record.needsConfirmation, record.phraseID == nil else {
                    throw EchoStoreError.invalidData("A model sentence cannot join the library before a parent confirms it.")
                }
                try text(record.english, max: 4_000, required: true)
                try text(record.chinese, max: 4_000, required: true)
            case "pending":
                guard record.needsConfirmation, record.phraseID == nil else {
                    throw EchoStoreError.invalidData("A pending line is waiting for a parent.")
                }
                try text(record.english, max: 4_000)
                try text(record.chinese, max: 4_000)
            default:
                guard !record.needsConfirmation, record.phraseID == nil else {
                    throw EchoStoreError.invalidData("Archived record is inconsistent.")
                }
                try text(record.english, max: 4_000)
                try text(record.chinese, max: 4_000)
            }
        }
        for clip in snapshot.clips {
            if let expressionID = clip.expressionID {
                guard clip.recordID == nil, expressions[expressionID]?.isConfirmed == true else {
                    throw EchoStoreError.invalidData("Recording has no confirmed expression.")
                }
            } else if let recordID = clip.recordID {
                guard recordIDs.contains(recordID), clip.role == "grandparent" || clip.role == "child" else {
                    throw EchoStoreError.invalidData("Recording has no speech record.")
                }
            } else {
                throw EchoStoreError.invalidData("Recording has no owner.")
            }
            guard clipRoles.contains(clip.role) else { throw EchoStoreError.invalidData("Unknown recording role.") }
            try filename(clip.filename)
            guard filenames.insert(clip.filename.lowercased()).inserted else { throw EchoStoreError.invalidData("Duplicate recording filename.") }
            try date(clip.createdAt)
        }
        for event in snapshot.events {
            let confirmed = expressions[event.expressionID]?.isConfirmed == true
            let inLibrary = libraryIDs.contains(event.expressionID)
            guard confirmed || inLibrary else { throw EchoStoreError.invalidData("Usage has no confirmed expression.") }
            guard (1...100_000).contains(event.count) else { throw EchoStoreError.invalidData("Invalid usage count.") }
            try date(event.createdAt)
        }
        if let exported = snapshot.settings.lastExportAt { try date(exported) }
    }

    /// Keep usage from growing without bound: one row per target per day is aggregated by the store,
    /// and each target keeps only the newest rows. Playback must never be able to fill the 100k cap.
    static func cappedEvents(_ events: [UsageEvent], otherRecords: Int) -> [UsageEvent] {
        var grouped: [UUID: [UsageEvent]] = [:]
        for event in events where event.count > 0 {
            grouped[event.expressionID, default: []].append(event)
        }
        var capped: [UsageEvent] = []
        for (_, items) in grouped {
            let newest = items.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) }
            capped.append(contentsOf: newest.prefix(maxEventsPerTarget))
        }
        let budget = max(0, eventWriteBudget - otherRecords)
        if capped.count > budget {
            capped.sort { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) }
            capped = Array(capped.prefix(budget))
        }
        return capped
    }

    static func newer<T>(_ a: T, _ b: T, date: (T) -> Date, id: (T) -> UUID) -> Bool {
        date(a) == date(b) ? id(a).uuidString < id(b).uuidString : date(a) > date(b)
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
        return EchoSnapshot(
            moments: value.moments.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            expressions: value.expressions.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            clips: value.clips.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            events: value.events.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            library: value.library.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            records: value.records.sorted { newer($0, $1, date: { $0.createdAt }, id: { $0.id }) },
            settings: value.settings)
    }
}
