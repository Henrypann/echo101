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

    @Test func vocabularyFileIsCompleteAndPinnedFirst() throws {
        let catalog = try VocabularyCatalog.load()
        let pinned = catalog.categories.filter(\.pinned)
        #expect(pinned.count == 1)
        #expect(catalog.categories.first?.id == "hangzhou")
        #expect(catalog.categories.first?.pinned == true)
        #expect(catalog.categories.map(\.id) == [
            "hangzhou", "food", "fruit", "animals", "colors", "numbers", "body",
            "clothes", "home", "toys", "transport", "weather", "family", "actions"
        ])
        #expect(catalog.categories.first?.words.allSatisfy { $0.emoji.isEmpty } == true)
        for category in catalog.categories {
            #expect(!category.words.isEmpty)
            if category.id == "hangzhou" { #expect((20...30).contains(category.words.count)) }
            for word in category.words {
                #expect(!word.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!word.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!word.exampleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!word.exampleZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                let count = word.exampleEn.split(whereSeparator: \.isWhitespace).count
                #expect((3...7).contains(count))
            }
        }
    }

    @Test func vocabularyImagesResolveAndHangzhouPhotosAreAttributed() throws {
        let catalog = try VocabularyCatalog.load()
        var pictured = 0
        var hangzhouPhotos = 0
        for category in catalog.categories {
            if !category.image.isEmpty {
                #expect(VocabularyImages.resourceURL(named: category.image) != nil)
            }
            let common = category.id != "hangzhou"
            for word in category.words {
                if common {
                    #expect(!word.image.isEmpty)
                    #expect(word.credit == nil)
                }
                guard !word.image.isEmpty else { continue }
                pictured += 1
                #expect(VocabularyImages.resourceURL(named: word.image) != nil)
                guard category.id == "hangzhou" else { continue }
                hangzhouPhotos += 1
                let credit = try #require(word.credit)
                #expect(!credit.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!credit.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(credit.licenseURL.hasPrefix("https://"))
                #expect(credit.sourceURL.hasPrefix("https://commons.wikimedia.org/"))
            }
        }
        #expect(pictured == 237)
        #expect(hangzhouPhotos == 26)
        #expect(VocabularyImages.openMojiAttribution.contains("CC BY-SA 4.0"))
    }

    @Test func seedLibraryIsOriginalEverydaySpeech() {
        let phrases = SeedLibrary.make()
        #expect(phrases.count >= 50)
        #expect(phrases.allSatisfy { $0.source == "seed" && !$0.chinese.isEmpty && !$0.english.isEmpty })
        #expect(phrases.contains { $0.english == "Don't touch that." })
    }

    @Test func libraryMatchWinsAndUnconfirmedNeverJoins() throws {
        let phrase = LibraryPhrase(chinese: "我想要苹果", english: "I want an apple.", keywords: ["苹果", "我想要苹果"])
        let hit = UtterancePlanner.plan(text: "苹果", phrases: [phrase], consent: true, modelReady: true)
        #expect(hit == .library(phrase))
        let pending = UtterancePlanner.plan(text: "火箭发射去火星基地", phrases: [phrase], consent: false, modelReady: true)
        #expect(pending == .savePending)
        let model = UtterancePlanner.plan(text: "火箭发射去火星基地", phrases: [phrase], consent: true, modelReady: true)
        #expect(model == .callModel)
        #expect(UtterancePlanner.plan(text: "   ", phrases: [phrase], consent: true, modelReady: true) == .unheard)

        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        let record = SpokenRecord(recognizedText: "火箭发射去火星基地", english: "Let's go to the moon.", chineseMeaning: "我们去月球。", kind: .pendingParent)
        try store.addSpokenRecord(record)
        #expect(store.rotationPhrases().isEmpty)
        #expect(!store.snapshot.phrases.contains { $0.english == "Let's go to the moon." })
        let saved = try store.confirmSpokenRecord(id: record.id, english: "Let's go to the moon.", chinese: "我们去月球。")
        #expect(store.snapshot.phrases == [saved])
        #expect(store.rotationPhrases().map(\.id) == [saved.id])
        #expect(store.snapshot.records.first?.kind == .confirmed)
    }

    @Test func playbackDoesNotRewriteTheLibrary() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        let moment = try store.createMoment(scene: "Food", note: "Apple")
        let expression = Expression(momentID: moment.id, text: "Apple", isConfirmed: true)
        try store.saveExpression(expression)
        let baseline = store.fullStoreSaveCount
        var saves = 0
        store.beforeSave = { saves += 1 }
        try store.recordUsage(expressionID: expression.id, kind: .play)
        try store.recordUsage(expressionID: expression.id, kind: .replay)
        #expect(saves == 0)
        #expect(store.fullStoreSaveCount == baseline)
        #expect(store.snapshot.events.count == 2)
        let reopened = try EchoStore(directory: directory)
        #expect(reopened.snapshot.events.map(\.kind) == store.snapshot.events.map(\.kind))
        #expect(reopened.snapshot.expressions.first?.lastUsedAt != nil)
    }

    @Test func usageCapCannotBlockLaterWrites() throws {
        let expressionID = UUID()
        var events: [UsageEvent] = []
        for index in 0..<100_001 {
            events.append(UsageEvent(expressionID: expressionID, createdAt: Date(timeIntervalSince1970: TimeInterval(index)), kind: .play))
        }
        let capped = EchoValidation.cappedEvents(events)
        #expect(capped.count == EchoValidation.maxUsagePerExpression)
        #expect(capped.count < 100_000)

        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        let moment = try store.createMoment(scene: "Food", note: "Apple")
        let expression = Expression(momentID: moment.id, text: "Apple", isConfirmed: true)
        try store.saveExpression(expression)
        for _ in 0..<40 { try store.recordUsage(expressionID: expression.id, kind: .play) }
        #expect(store.snapshot.events.count <= EchoValidation.maxUsagePerExpression)
        _ = try store.createMoment(scene: "Toys", note: "Still writable")
        #expect(store.snapshot.moments.count == 2)
    }

    @Test func wordStarsDoNotRewriteTheLibrary() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        let baseline = store.fullStoreSaveCount
        try store.markWordRepeated("apple")
        try store.markWordRepeated("apple")
        try store.markWordRepeated("west-lake")
        #expect(store.fullStoreSaveCount == baseline)
        #expect(store.repeatedWordIDs == ["apple", "west-lake"])
        let reopened = try EchoStore(directory: directory)
        #expect(reopened.repeatedWordIDs == ["apple", "west-lake"])
        #expect(reopened.fullStoreSaveCount == baseline)
    }

    @Test func exportCopyIsRemovedAndLaunchClearsLeftovers() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory)
        #expect(store.snapshot.exportIsOverdue)
        let archive = try store.exportArchive(includeAudio: false)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        #expect(store.snapshot.lastExportAt != nil)
        #expect(!store.snapshot.exportIsOverdue)
        try store.discardExport(at: archive)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        let exports = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let leftover = exports.appendingPathComponent("Echo101-\(UUID().uuidString).echo101")
        try Data("private archive".utf8).write(to: leftover)
        _ = try EchoStore(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }

    @Test func versionOneStoreAndArchiveMigrateForward() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EchoStore(directory: directory.appendingPathComponent("Live"))
        _ = try store.createMoment(scene: "Temp", note: "temp")
        let moment = Moment(scene: "Food", note: "老人说想吃苹果")
        let kept = Expression(momentID: moment.id, text: "I want an apple.", meaning: "我想要苹果。", isConfirmed: true)
        let draft = Expression(momentID: moment.id, text: "A red car.", meaning: "一辆红色小汽车。", isConfirmed: false)
        let legacy = EchoSnapshot(moments: [moment], expressions: [kept, draft])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        for key in ["phrases", "records", "consentGrantedAt", "allowCellular", "lastExportAt", "setupIssues"] {
            object.removeValue(forKey: key)
        }
        let payload = try JSONSerialization.data(withJSONObject: object)
        let request = NSFetchRequest<NSManagedObject>(entityName: "EchoState")
        let state = try #require(store.context.fetch(request).first)
        state.setValue(1, forKey: "version")
        state.setValue(payload, forKey: "payload")
        try store.context.save()
        let migrated = try EchoStore(directory: store.directory)
        #expect(migrated.snapshot.expressions.count == 2)
        #expect(migrated.snapshot.phrases.count == 1)
        #expect(migrated.snapshot.phrases.first?.source == "migrated")
        #expect(migrated.snapshot.phrases.first?.english == "I want an apple.")
        #expect(migrated.snapshot.records.count == 2)
        #expect(migrated.snapshot.records.contains { $0.kind == .pendingParent && $0.phraseID == nil })
        let stored = try #require(migrated.context.fetch(request).first)
        #expect(Self.version(stored.value(forKey: "version")) == EchoValidation.schemaVersion)
        stored.setValue(99, forKey: "version")
        try migrated.context.save()
        #expect(throws: EchoStoreError.unsupportedVersion) { try EchoStore(directory: store.directory) }

        let archive = directory.appendingPathComponent("v1.echo101")
        let archiveObject: [String: Any] = [
            "format": "Echo101", "formatVersion": 1, "schemaVersion": 1,
            "snapshot": object, "audio": []
        ]
        try JSONSerialization.data(withJSONObject: archiveObject).write(to: archive)
        let empty = try EchoStore(directory: directory.appendingPathComponent("Empty"))
        try empty.restoreArchive(fromURL: archive)
        #expect(empty.snapshot.phrases.count == 1)
        #expect(empty.snapshot.expressions.first?.text == "I want an apple." || empty.snapshot.expressions.last?.text == "I want an apple.")
        #expect(throws: EchoStoreError.restoreRequiresEmptyStore) { try empty.restoreArchive(fromURL: archive) }
    }

    private static func version(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
