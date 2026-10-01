import CoreData
import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
@MainActor
struct EchoProductTests {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("Echo101-Product-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func phrase(_ english: String, _ chinese: String, keywords: [String] = []) -> LibraryPhrase {
        LibraryPhrase(english: english, chinese: chinese, scene: "日常", keywords: keywords, source: "parent")
    }

    @Test func seedLibraryIsOriginalAndWithinBounds() {
        let phrases = SeedLibrary.phrases
        #expect((50...100).contains(phrases.count))
        #expect(Set(phrases.map(\.id)).count == phrases.count)
        #expect(Set(phrases.map { $0.english.lowercased() }).count == phrases.count)
        #expect(phrases.allSatisfy { $0.source == "seed" && !$0.english.isEmpty && !$0.chinese.isEmpty })
        #expect(phrases.contains { $0.english == "Don't touch that." })
    }

    @Test func libraryMatchWinsAndModelIsOnlyAFallback() {
        let library = [
            phrase("Let's wash our hands.", "我们去洗手。", keywords: ["洗手", "洗洗手"]),
            phrase("Don't touch that.", "不要碰那个。", keywords: ["不要碰", "别碰"])
        ]
        let wash = PhraseMatcher.plan(utterance: "奶奶说洗洗手", library: library, modelAllowed: true)
        guard case .library(let matched) = wash else {
            Issue.record("Expected a library match")
            return
        }
        #expect(matched.english == "Let's wash our hands.")
        let unknown = PhraseMatcher.plan(utterance: "阳台那盆花开了", library: library, modelAllowed: true)
        #expect(unknown == .askModel)
        let offline = PhraseMatcher.plan(utterance: "阳台那盆花开了", library: library, modelAllowed: false)
        #expect(offline == .saveForParent)
        #expect(PhraseMatcher.bestMatch(utterance: "不要碰那个杯子", library: library)?.phrase.english == "Don't touch that.")
    }

    @Test func generatedLineNeverJoinsLibraryOrRotationUntilParentConfirms() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        try store.addLibraryPhrase(phrase("Milk, please.", "请给我牛奶。", keywords: ["牛奶"]))
        let before = store.snapshot.library
        let rotationBefore = store.snapshot.rotationPhrases.map(\.id)
        let generated = PhraseMatcher.generatedRecord(utterance: "宝宝要喝水", english: "Water, please.", chinese: "请给我水。")
        try store.saveRecord(generated)
        #expect(store.snapshot.library == before)
        #expect(store.snapshot.rotationPhrases.map(\.id) == rotationBefore)
        #expect(store.snapshot.records.first?.needsConfirmation == true)
        #expect(store.snapshot.records.first?.phraseID == nil)
        let pending = PhraseMatcher.pendingRecord(utterance: "这句先记下")
        try store.saveRecord(pending)
        #expect(store.snapshot.library == before)
        let confirmed = try store.confirmRecord(id: generated.id, english: "Water, please.", chinese: "请给我水。", scene: "吃饭")
        #expect(store.snapshot.library.contains { $0.id == confirmed.id && $0.english == "Water, please." })
        #expect(store.snapshot.rotationPhrases.contains { $0.id == confirmed.id })
        let saved = try #require(store.snapshot.records.first { $0.id == generated.id })
        #expect(!saved.needsConfirmation)
        #expect(saved.origin == "library")
        #expect(saved.phraseID == confirmed.id)
        #expect(store.snapshot.records.first { $0.id == pending.id }?.needsConfirmation == true)
        #expect(!store.snapshot.library.contains { $0.english == pending.english && $0.id == pending.id })
    }

    @Test func playbackDoesNotRewriteTheFullStore() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        let moment = try store.createMoment(scene: "Food", note: "apple")
        let expression = Expression(momentID: moment.id, text: "I want an apple.", meaning: "我想要苹果。")
        try store.saveExpression(expression)
        let baseline = store.fullSaveCount
        var saves = 0
        store.beforeSave = { saves += 1 }
        try store.recordUsage(expressionID: expression.id, kind: .play)
        try store.recordUsage(expressionID: expression.id, kind: .play)
        try store.recordUsage(expressionID: expression.id, kind: .replay)
        #expect(saves == 0)
        #expect(store.fullSaveCount == baseline)
        let play = try #require(store.snapshot.events.first { $0.kind == .play && $0.expressionID == expression.id })
        #expect(play.count == 2)
        let reopened = try EchoStore(directory: directory)
        let replayed = try #require(reopened.snapshot.events.first { $0.kind == .play && $0.expressionID == expression.id })
        #expect(replayed.count == 2)
        #expect(reopened.fullSaveCount == 0)
        try store.flushUsage()
        #expect(store.fullSaveCount == baseline + 1)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("UsageOverlay.json").path))
    }

    @Test func usageCannotGrowEnoughToBlockWrites() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        let moment = try store.createMoment(scene: "Toys", note: "car")
        let expression = Expression(momentID: moment.id, text: "A red car.")
        try store.saveExpression(expression)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for day in 0..<40 {
            try store.recordUsage(expressionID: expression.id, kind: .play, at: start.addingTimeInterval(Double(day) * 86_400))
        }
        let kept = store.snapshot.events.filter { $0.expressionID == expression.id }
        #expect(kept.count == EchoValidation.maxEventsPerTarget)
        #expect(kept.count < 100_000)
        let extra = try store.createMoment(scene: "Food", note: "still writable")
        #expect(store.snapshot.moments.contains { $0.id == extra.id })
        let replayDay = start.addingTimeInterval(40 * 86_400)
        for _ in 0..<30 {
            try store.recordUsage(expressionID: expression.id, kind: .replay, at: replayDay)
        }
        let sameDay = store.snapshot.events.filter { $0.expressionID == expression.id && $0.kind == .replay }
        #expect(sameDay.count == 1)
        #expect(sameDay.first?.count == 30)
    }

    @Test func exportCopiesAreDeletedAndClearedOnLaunch() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        _ = try store.createMoment(scene: "Everyday", note: "hello")
        let exported = try store.exportArchive(includeAudio: false)
        #expect(FileManager.default.fileExists(atPath: exported.path))
        try store.removeExportFile(at: exported)
        #expect(!FileManager.default.fileExists(atPath: exported.path))
        let outside = directory.appendingPathComponent("keep.echo101")
        try Data("keep".utf8).write(to: outside)
        #expect(throws: EchoStoreError.unsafeFile) { try store.removeExportFile(at: outside) }
        #expect(FileManager.default.fileExists(atPath: outside.path))
        try FileManager.default.createDirectory(at: store.exportsDirectory, withIntermediateDirectories: true)
        let leftover = store.exportsDirectory.appendingPathComponent("Echo101-\(UUID().uuidString).echo101")
        try Data("leftover".utf8).write(to: leftover)
        let linked = directory.appendingPathComponent("linked-export.echo101")
        try Data("linked".utf8).write(to: linked)
        try FileManager.default.createSymbolicLink(at: store.exportsDirectory.appendingPathComponent("link.echo101"), withDestinationURL: linked)
        _ = try EchoStore(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(try Data(contentsOf: linked) == Data("linked".utf8))
        #expect(FileManager.default.fileExists(atPath: store.exportsDirectory.appendingPathComponent("link.echo101").path))
    }

    @Test func versionOneStoreAndArchiveMigrateForward() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let moment = Moment(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000), scene: "Food", note: "apple")
        let confirmed = Expression(id: UUID(), momentID: moment.id, createdAt: moment.createdAt, text: "I want an apple.", meaning: "我想要苹果。", isConfirmed: true, source: "manual")
        let draft = Expression(id: UUID(), momentID: moment.id, createdAt: moment.createdAt.addingTimeInterval(5), text: "Secret draft.", meaning: "草稿", isConfirmed: false, source: "model")
        let legacy = EchoSnapshotV1(moments: [moment], expressions: [confirmed, draft], clips: [], events: [
            UsageEvent(expressionID: confirmed.id, createdAt: moment.createdAt, kind: .play)
        ])
        let payload = try JSONEncoder().encode(legacy)
        let starter = try EchoStore(directory: directory)
        _ = try starter.createMoment(scene: "Temp", note: "temp")
        let request = NSFetchRequest<NSManagedObject>(entityName: "EchoState")
        let state = try #require(try starter.context.fetch(request).first)
        state.setValue(1, forKey: "version")
        state.setValue(payload, forKey: "payload")
        try starter.context.save()
        let migrated = try EchoStore(directory: directory)
        #expect(migrated.snapshot.library.contains { $0.english == "I want an apple." && $0.chinese == "我想要苹果。" && $0.id != confirmed.id })
        #expect(!migrated.snapshot.library.contains { $0.english == "Secret draft." })
        #expect(migrated.snapshot.expressions.count == 2)
        #expect(migrated.snapshot.events.contains { $0.expressionID == confirmed.id && $0.count == 1 })
        let stored = try #require(try migrated.context.fetch(request).first)
        let storedVersion = stored.value(forKey: "version") as? Int ?? (stored.value(forKey: "version") as? NSNumber)?.intValue
        #expect(storedVersion == EchoValidation.schemaVersion)
        #expect(EchoValidation.schemaVersion == 2)

        let snapshotObject = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let wrapper: [String: Any] = ["format": "Echo101", "formatVersion": 1, "schemaVersion": 1, "snapshot": snapshotObject, "audio": []]
        let archiveURL = directory.appendingPathComponent("v1.echo101")
        try JSONSerialization.data(withJSONObject: wrapper).write(to: archiveURL)
        let restored = try EchoStore(directory: directory.appendingPathComponent("Restored"))
        try restored.restoreArchive(fromURL: archiveURL)
        #expect(restored.snapshot.library.contains { $0.english == "I want an apple." })
        #expect(!restored.snapshot.library.contains { $0.english == "Secret draft." })

        let future = directory.appendingPathComponent("future.echo101")
        var futureWrapper = wrapper
        futureWrapper["schemaVersion"] = 3
        try JSONSerialization.data(withJSONObject: futureWrapper).write(to: future)
        let empty = try EchoStore(directory: directory.appendingPathComponent("Empty"))
        #expect(throws: EchoStoreError.unsupportedVersion) { try empty.restoreArchive(fromURL: future) }
        #expect(empty.snapshot.isEmpty)
    }

    @Test func pristineSeedCanBeReplacedByRestore() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = try EchoStore(directory: directory.appendingPathComponent("Source"))
        let moment = try source.createMoment(scene: "出门", note: "出去")
        try source.saveExpression(Expression(momentID: moment.id, text: "Let's go outside.", meaning: "我们出门。"))
        let archive = try source.exportArchive(includeAudio: false)
        let target = try EchoStore(directory: directory.appendingPathComponent("Target"))
        try target.installSeedLibrary()
        #expect(target.snapshot.isPristineSeededLibrary)
        try target.restoreArchive(fromURL: archive)
        #expect(target.snapshot.expressions.contains { $0.text == "Let's go outside." })
        #expect(!target.snapshot.library.contains { $0.source == "seed" && $0.english == "Bath time." })
    }

    @Test func lastExportTimeIsStored() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        #expect(store.snapshot.settings.lastExportAt == nil)
        let when = Date(timeIntervalSince1970: 1_720_000_000)
        try store.markExported(at: when)
        #expect(store.snapshot.settings.lastExportAt == when)
        #expect(try EchoStore(directory: directory).snapshot.settings.lastExportAt == when)
    }
}
