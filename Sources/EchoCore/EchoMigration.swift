import Foundation

enum EchoMigration {
    static func snapshot(from payload: Data, storedVersion: Int) throws -> EchoSnapshot {
        switch storedVersion {
        case 1:
            let legacy = try JSONDecoder().decode(EchoSnapshotV1.self, from: payload)
            return upgrade(legacy)
        case EchoValidation.schemaVersion:
            var current = try JSONDecoder().decode(EchoSnapshot.self, from: payload)
            current.events = EchoValidation.cappedEvents(current.events, otherRecords: otherCount(current))
            return current
        default:
            throw EchoStoreError.unsupportedVersion
        }
    }

    static func upgrade(_ legacy: EchoSnapshotV1) -> EchoSnapshot {
        var library: [LibraryPhrase] = []
        var seenEnglish = Set<String>()
        for expression in legacy.expressions where expression.isConfirmed {
            let key = expression.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard seenEnglish.insert(key).inserted else { continue }
            let scene = legacy.moments.first { $0.id == expression.momentID }?.scene ?? "Everyday"
            // New id: expression ids stay on the old rows, and the 100k check is global.
            library.append(LibraryPhrase(
                id: UUID(),
                createdAt: expression.createdAt,
                english: expression.text,
                chinese: expression.meaning,
                scene: scene,
                keywords: [],
                source: expression.source.isEmpty ? "migrated" : expression.source,
                lastUsedAt: expression.lastUsedAt
            ))
        }
        var snapshot = EchoSnapshot(
            moments: legacy.moments,
            expressions: legacy.expressions,
            clips: legacy.clips,
            events: legacy.events,
            library: library,
            records: [],
            settings: EchoSettings()
        )
        snapshot.events = EchoValidation.cappedEvents(snapshot.events, otherRecords: otherCount(snapshot))
        return snapshot
    }

    private static func otherCount(_ snapshot: EchoSnapshot) -> Int {
        snapshot.moments.count + snapshot.expressions.count + snapshot.clips.count + snapshot.library.count + snapshot.records.count
    }
}
