import Foundation

enum EchoMigration {
    /// Read a snapshot stored at `version` and return the current shape.
    /// Versions newer than `EchoValidation.schemaVersion` are rejected by the caller.
    static func migrate(_ snapshot: EchoSnapshot, from version: Int) -> EchoSnapshot {
        guard version < EchoValidation.schemaVersion else { return snapshot }
        var next = snapshot
        if version <= 1, next.phrases.isEmpty, next.records.isEmpty {
            let scenes = Dictionary(uniqueKeysWithValues: snapshot.moments.map { ($0.id, $0.scene) })
            let notes = Dictionary(uniqueKeysWithValues: snapshot.moments.map { ($0.id, $0.note) })
            for expression in snapshot.expressions {
                let scene = scenes[expression.momentID] ?? "Everyday"
                let chinese = expression.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "待补充" : expression.meaning
                if expression.isConfirmed {
                    let phrase = LibraryPhrase(
                        createdAt: expression.createdAt,
                        chinese: chinese,
                        english: expression.text,
                        spokenEnglish: expression.spokenText,
                        scene: scene.isEmpty ? "Everyday" : scene,
                        keywords: keywords(from: chinese),
                        source: "migrated")
                    next.phrases.append(phrase)
                    next.records.append(SpokenRecord(
                        createdAt: expression.createdAt,
                        recognizedText: notes[expression.momentID] ?? chinese,
                        english: expression.text,
                        chineseMeaning: chinese,
                        phraseID: phrase.id,
                        kind: .library))
                } else {
                    next.records.append(SpokenRecord(
                        createdAt: expression.createdAt,
                        recognizedText: notes[expression.momentID] ?? expression.text,
                        english: expression.text,
                        chineseMeaning: chinese,
                        phraseID: nil,
                        kind: .pendingParent))
                }
            }
        }
        next.events = EchoValidation.cappedEvents(next.events)
        return next
    }

    private static func keywords(from chinese: String) -> [String] {
        let trimmed = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "待补充" else { return [] }
        return [trimmed]
    }
}
