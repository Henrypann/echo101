import Foundation
import Testing
@testable import EchoCore

private typealias Expression = EchoCore.Expression

@Suite(.serialized)
@MainActor
struct EchoCoreTests {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("Echo101-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func seeded(_ directory: URL, confirmed: Bool = true) throws -> (EchoStore, Moment, Expression) {
        let store = try EchoStore(directory: directory)
        let moment = try store.createMoment(scene: "Coffee shop", note: "Ask for a table")
        let expression = Expression(momentID: moment.id, text: "A table for two, please.", isConfirmed: confirmed)
        try store.saveExpression(expression)
        return (store, moment, expression)
    }

    private func audio(_ store: EchoStore, expression: Expression) throws -> VoiceClip {
        let url = store.temporaryDirectory.appendingPathComponent("synthetic.m4a")
        try Data("synthetic audio bytes".utf8).write(to: url)
        return try store.addVoiceClip(expressionID: expression.id, temporaryURL: url)
    }

    private enum Fault: Error { case save }

    @Test func parentTipSurvivesPersistenceAndArchive() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory.appendingPathComponent("Source"))
        var updated = expression; updated.parentTip = "一起收玩具时说，不要求完整跟读。"
        try store.saveExpression(updated)
        #expect(try EchoStore(directory: store.directory).snapshot.expressions.first?.parentTip == updated.parentTip)
        let archive = try store.exportArchive(includeAudio: false)
        let restored = try EchoStore(directory: directory.appendingPathComponent("Restored"))
        try restored.restoreArchive(fromURL: archive)
        #expect(restored.snapshot.expressions.first?.parentTip == updated.parentTip)
    }

    @Test func oldExpressionWithoutParentTipStillDecodes() throws {
        let expression = Expression(momentID: UUID(), text: "A red car.")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(expression)) as? [String: Any])
        legacy.removeValue(forKey: "parentTip")
        let decoded = try JSONDecoder().decode(Expression.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.parentTip == nil)
        #expect(decoded.text == expression.text)
    }

    @Test func invalidParentTipCannotChangeLibrary() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory)
        let before = store.snapshot
        for tip in [String(repeating: "x", count: 1001), "unsafe\0text"] {
            var updated = expression; updated.parentTip = tip
            #expect(throws: (any Error).self) { try store.saveExpression(updated) }
            #expect(store.snapshot == before)
        }
    }

    @Test func batchExpressionSaveIsAtomic() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, moment, _) = try seeded(directory)
        let before = store.snapshot
        let first = Expression(momentID: moment.id, text: "Valid candidate", isConfirmed: false)
        let broken = Expression(momentID: UUID(), text: "Missing moment", isConfirmed: false)
        #expect(throws: (any Error).self) { try store.saveExpressions([first, broken]) }
        #expect(store.snapshot == before)
        #expect(try EchoStore(directory: directory).snapshot == before)
        #expect(throws: (any Error).self) { try store.saveExpressions([first, first]) }
        let second = Expression(momentID: moment.id, text: "Second candidate", isConfirmed: false)
        store.beforeSave = { throw Fault.save }
        #expect(throws: Fault.self) { try store.saveExpressions([first, second]) }
        #expect(store.snapshot == before)
        #expect(try EchoStore(directory: directory).snapshot == before)
        store.beforeSave = nil
        try store.saveExpressions([first, second])
        #expect(store.snapshot.expressions.count == before.expressions.count + 2)
        #expect(try EchoStore(directory: directory).snapshot == store.snapshot)
    }

    @Test func crudPersistsAcrossReopen() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, moment, expression) = try seeded(directory)
        var edited = moment; edited.note = "Window seat"
        try store.updateMoment(edited)
        var updated = expression; updated.meaning = "Request seating"
        try store.saveExpression(updated)
        try store.recordUsage(expressionID: expression.id, kind: .play)
        try store.toggleFavorite(id: expression.id)
        let reopened = try EchoStore(directory: directory)
        #expect(reopened.snapshot == store.snapshot)
        #expect(reopened.snapshot.moments.first?.note == "Window seat")
        #expect(reopened.snapshot.expressions.first?.isFavorite == true)
        #expect(reopened.snapshot.events.count == 2)
        try store.deleteExpression(id: expression.id)
        #expect(store.snapshot.events.isEmpty)
        try store.deleteMoment(id: moment.id)
        #expect(store.snapshot.isEmpty)
    }

    @Test func confirmationGateAndReferentialIntegrity() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, draft) = try seeded(directory, confirmed: false)
        #expect(throws: EchoStoreError.confirmationRequired) { try store.recordUsage(expressionID: draft.id, kind: .play) }
        #expect(throws: EchoStoreError.confirmationRequired) { try store.toggleFavorite(id: draft.id) }
        #expect(throws: EchoStoreError.confirmationRequired) { try audio(store, expression: draft) }
        #expect(throws: (any Error).self) { try store.saveExpression(Expression(momentID: UUID(), text: "Dangling")) }
        #expect(throws: (any Error).self) { try store.createMoment(scene: "", note: "") }
        #expect(throws: (any Error).self) { try store.createMoment(scene: "Test", note: String(repeating: "x", count: 10_001)) }
        #expect(store.snapshot.events.isEmpty)
        #expect(store.snapshot.clips.isEmpty)
        #expect(store.snapshot.expressions.count == 1)
    }

    @Test func confirmedOrderingAndUsage() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, moment, first) = try seeded(directory)
        let second = Expression(momentID: moment.id, createdAt: Date().addingTimeInterval(100), text: "Second")
        let draft = Expression(momentID: moment.id, text: "Draft", isConfirmed: false)
        try store.saveExpression(second); try store.saveExpression(draft)
        #expect(store.snapshot.confirmedExpressions.map(\.id) == [second.id, first.id])
        try store.toggleFavorite(id: first.id)
        #expect(store.snapshot.confirmedExpressions.map(\.id) == [first.id, second.id])
        try store.recordUsage(expressionID: first.id, kind: .replay)
        #expect(store.snapshot.events.first?.kind == .replay)
        #expect(store.snapshot.expressions.first(where: { $0.id == first.id })?.lastUsedAt != nil)
    }

    @Test func audioAndCascadingDeletion() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, moment, expression) = try seeded(directory)
        let clip = try audio(store, expression: expression)
        let clipURL = try store.clipURL(for: clip)
        #expect(FileManager.default.fileExists(atPath: clipURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.temporaryDirectory.appendingPathComponent("synthetic.m4a").path))
        let reopened = try EchoStore(directory: directory)
        #expect(try Data(contentsOf: reopened.clipURL(for: clip)) == Data("synthetic audio bytes".utf8))
        try store.recordUsage(expressionID: expression.id, kind: .play)
        try store.deleteMoment(id: moment.id)
        #expect(store.snapshot.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: clipURL.path))
    }

    @Test func failedSavePreservesPublishedAndPersistentStateAndAudio() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, moment, expression) = try seeded(directory)
        let clip = try audio(store, expression: expression)
        let url = try store.clipURL(for: clip)
        let before = store.snapshot
        store.beforeSave = { throw Fault.save }
        #expect(throws: Fault.self) { try store.deleteMoment(id: moment.id) }
        #expect(store.snapshot == before)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try EchoStore(directory: directory).snapshot == before)
        #expect(throws: Fault.self) { try audio(store, expression: expression) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.recordingsDirectory.path).count == 1)
        #expect(FileManager.default.fileExists(atPath: store.temporaryDirectory.appendingPathComponent("synthetic.m4a").path))
        store.beforeSave = nil
        try store.deleteClip(id: clip.id)
        #expect(store.snapshot.clips.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func noAudioExportRestoresWithoutClipReferences() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory.appendingPathComponent("Source"))
        _ = try audio(store, expression: expression)
        let archiveURL = try store.exportArchive(includeAudio: false)
        let archive = try JSONDecoder().decode(EchoArchive.self, from: Data(contentsOf: archiveURL))
        #expect(archive.snapshot.clips.isEmpty && archive.audio.isEmpty)
        let restored = try EchoStore(directory: directory.appendingPathComponent("Target"))
        try restored.restoreArchive(fromURL: archiveURL)
        #expect(restored.snapshot.moments == store.snapshot.moments)
        #expect(restored.snapshot.expressions == store.snapshot.expressions)
        #expect(restored.snapshot.clips.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: restored.recordingsDirectory.path).isEmpty)
        #expect(store.snapshot.clips.count == 1)
    }

    @Test func audioArchiveRoundTripAndNonEmptyProtection() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory.appendingPathComponent("Source"))
        let clip = try audio(store, expression: expression)
        try store.recordUsage(expressionID: expression.id, kind: .play)
        let archive = try store.exportArchive(includeAudio: true)
        let targetDirectory = directory.appendingPathComponent("Target")
        let restored = try EchoStore(directory: targetDirectory)
        try restored.restoreArchive(fromURL: archive)
        #expect(restored.snapshot == store.snapshot)
        #expect(try Data(contentsOf: restored.clipURL(for: clip)) == Data(contentsOf: store.clipURL(for: clip)))
        #expect(try EchoStore(directory: targetDirectory).snapshot == store.snapshot)
        #expect(throws: EchoStoreError.restoreRequiresEmptyStore) { try restored.restoreArchive(fromURL: archive) }
    }

    @Test func invalidArchivesAreRejectedBeforeImport() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory.appendingPathComponent("Source"))
        _ = try audio(store, expression: expression)
        let exported = try store.exportArchive(includeAudio: true)
        let original = try JSONDecoder().decode(EchoArchive.self, from: Data(contentsOf: exported))
        let target = try EchoStore(directory: directory.appendingPathComponent("Target"))
        let corrupted = directory.appendingPathComponent("corrupt.echo101")
        func attempt(_ change: (inout EchoArchive) -> Void) throws {
            var archive = original; change(&archive)
            try JSONEncoder().encode(archive).write(to: corrupted)
            #expect(throws: (any Error).self) { try target.restoreArchive(fromURL: corrupted) }
            #expect(target.snapshot.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: target.recordingsDirectory.path).isEmpty)
        }
        try attempt { $0.formatVersion = 99 }
        try attempt { $0.schemaVersion = 99 }
        try attempt { $0.audio[0].sha256 = String(repeating: "0", count: 64) }
        try attempt { $0.audio[0].byteCount += 1 }
        try attempt { $0.audio[0].data = Data("altered".utf8) }
        try attempt { $0.audio[0].filename = "../escape.m4a"; $0.snapshot.clips[0].filename = "../escape.m4a" }
        try attempt { $0.snapshot.expressions[0].momentID = UUID() }
        try attempt { $0.snapshot.expressions.append($0.snapshot.expressions[0]) }
        try attempt { $0.audio = [] }
        try attempt { $0.snapshot.expressions[0].isConfirmed = false }
    }

    @Test func importSaveFailureRollsBackAllInstalledFiles() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (source, _, expression) = try seeded(directory.appendingPathComponent("Source"))
        _ = try audio(source, expression: expression)
        let archive = try source.exportArchive(includeAudio: true)
        let targetDirectory = directory.appendingPathComponent("Target")
        let target = try EchoStore(directory: targetDirectory)
        target.beforeSave = { throw Fault.save }
        #expect(throws: Fault.self) { try target.restoreArchive(fromURL: archive) }
        #expect(target.snapshot.isEmpty)
        #expect(try EchoStore(directory: targetDirectory).snapshot.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.recordingsDirectory.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).allSatisfy { !$0.hasPrefix("Import-") })
        target.beforeSave = nil
        try target.restoreArchive(fromURL: archive)
        #expect(target.snapshot == source.snapshot)
    }

    @Test func restoreDoesNotOverwriteExistingRecording() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (source, _, expression) = try seeded(directory.appendingPathComponent("Source"))
        let clip = try audio(source, expression: expression)
        let archive = try source.exportArchive(includeAudio: true)
        let target = try EchoStore(directory: directory.appendingPathComponent("Target"))
        let existing = target.recordingsDirectory.appendingPathComponent(clip.filename)
        let preserved = Data("preserved".utf8); try preserved.write(to: existing)
        #expect(throws: EchoStoreError.unsafeFile) { try target.restoreArchive(fromURL: archive) }
        #expect(try Data(contentsOf: existing) == preserved)
        #expect(target.snapshot.isEmpty)
    }

    @Test func symlinkAndTraversalRecordingSafety() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory.appendingPathComponent("Store"))
        let external = directory.appendingPathComponent("external.m4a")
        try Data("external".utf8).write(to: external)
        #expect(throws: EchoStoreError.unsafeFile) { try store.addVoiceClip(expressionID: expression.id, temporaryURL: external) }
        let link = store.temporaryDirectory.appendingPathComponent("link.m4a")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        #expect(throws: EchoStoreError.unsafeFile) { try store.addVoiceClip(expressionID: expression.id, temporaryURL: link) }
        let clip = try audio(store, expression: expression)
        let permanent = try store.clipURL(for: clip)
        try FileManager.default.removeItem(at: permanent)
        try FileManager.default.createSymbolicLink(at: permanent, withDestinationURL: external)
        #expect(throws: EchoStoreError.unsafeFile) { try store.clipURL(for: clip) }
        #expect(throws: EchoStoreError.recordingCleanupIncomplete) { try store.deleteClip(id: clip.id) }
        #expect(store.snapshot.clips.isEmpty)
        #expect(try Data(contentsOf: external) == Data("external".utf8))
        let linkedRoot = directory.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: directory.appendingPathComponent("Store"))
        #expect(throws: EchoStoreError.unsafeFile) { try EchoStore(directory: linkedRoot) }
    }

    @Test func initCleansOnlyDirectRawTemporaryFiles() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, _) = try seeded(directory)
        let raw = store.temporaryDirectory.appendingPathComponent("abandoned.m4a")
        try Data("raw".utf8).write(to: raw)
        let nested = store.temporaryDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedFile = nested.appendingPathComponent("keep.m4a")
        try Data("nested".utf8).write(to: nestedFile)
        let external = directory.appendingPathComponent("keep.m4a")
        try Data("outside".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: store.temporaryDirectory.appendingPathComponent("link.m4a"), withDestinationURL: external)
        _ = try EchoStore(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: raw.path))
        #expect(FileManager.default.fileExists(atPath: nestedFile.path))
        #expect(try Data(contentsOf: external) == Data("outside".utf8))
    }

    @Test func restartCleansOnlyControlledUnreferencedRecordings() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory)
        let clip = try audio(store, expression: expression)
        let referenced = try store.clipURL(for: clip)
        let orphan = store.recordingsDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data("orphan".utf8).write(to: orphan)
        let unknown = store.recordingsDirectory.appendingPathComponent("user-notes.m4a")
        let wrongExtension = store.recordingsDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("unknown".utf8).write(to: unknown)
        try Data("unknown extension".utf8).write(to: wrongExtension)
        let nested = store.recordingsDirectory.appendingPathComponent(UUID().uuidString + ".wav", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedFile = nested.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data("nested".utf8).write(to: nestedFile)
        let external = directory.appendingPathComponent("outside.m4a")
        try Data("outside".utf8).write(to: external)
        let link = store.recordingsDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let reopened = try EchoStore(directory: directory)
        #expect(reopened.snapshot == store.snapshot)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(try Data(contentsOf: referenced) == Data("synthetic audio bytes".utf8))
        #expect(try Data(contentsOf: unknown) == Data("unknown".utf8))
        #expect(try Data(contentsOf: wrongExtension) == Data("unknown extension".utf8))
        #expect(try Data(contentsOf: nestedFile) == Data("nested".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == external.path)
        #expect(try Data(contentsOf: external) == Data("outside".utf8))
    }

    @Test func deletionCleanupFailureIsReportedAndRetriedAtRestart() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory)
        let clip = try audio(store, expression: expression)
        let url = try store.clipURL(for: clip)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: store.recordingsDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.recordingsDirectory.path) }
        #expect(throws: EchoStoreError.recordingCleanupIncomplete) { try store.deleteClip(id: clip.id) }
        #expect(store.snapshot.clips.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let reopened = try EchoStore(directory: directory)
        #expect(reopened.snapshot.clips.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let alreadyMissing = try audio(reopened, expression: expression)
        try FileManager.default.removeItem(at: reopened.clipURL(for: alreadyMissing))
        try reopened.deleteClip(id: alreadyMissing.id)
        #expect(reopened.snapshot.clips.isEmpty)
    }

    @Test func oversizedArchiveAndRecordingAreRejected() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory)
        let huge = store.temporaryDirectory.appendingPathComponent("large.m4a")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(EchoValidation.maxArchiveBytes + 1)); try handle.close()
        #expect(throws: EchoStoreError.archiveTooLarge) { try store.addVoiceClip(expressionID: expression.id, temporaryURL: huge) }
        let empty = try EchoStore(directory: directory.appendingPathComponent("Empty"))
        #expect(throws: EchoStoreError.archiveTooLarge) { try empty.restoreArchive(fromURL: huge) }
        #expect(empty.snapshot.isEmpty)
    }

    @Test func restartCleansOnlyControlledInterruptedImportDirectories() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, expression) = try seeded(directory)
        let clip = try audio(store, expression: expression)
        let stage = directory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        let emptyStage = directory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        let unknownStage = directory.appendingPathComponent("Import-not-a-uuid", isDirectory: true)
        for folder in [stage, emptyStage, unknownStage] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        let staged = stage.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data("interrupted copy".utf8).write(to: staged)
        let unknown = unknownStage.appendingPathComponent("keep.txt")
        try Data("unknown".utf8).write(to: unknown)
        let reopened = try EchoStore(directory: directory)
        #expect(reopened.snapshot == store.snapshot)
        #expect(!FileManager.default.fileExists(atPath: stage.path))
        #expect(!FileManager.default.fileExists(atPath: emptyStage.path))
        #expect(try Data(contentsOf: unknown) == Data("unknown".utf8))
        #expect(try Data(contentsOf: reopened.clipURL(for: clip)) == Data("synthetic audio bytes".utf8))
    }

    @Test func interruptedImportWithUnknownContentIsFullyPreservedAndReported() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, _) = try seeded(directory)
        let before = store.snapshot
        let stage = directory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let controlled = stage.appendingPathComponent(UUID().uuidString + ".wav")
        let unknown = stage.appendingPathComponent("readme.txt")
        try Data("controlled".utf8).write(to: controlled)
        try Data("unknown".utf8).write(to: unknown)
        #expect(throws: EchoStoreError.importRecoveryRequiresAttention) { try EchoStore(directory: directory) }
        #expect(try Data(contentsOf: controlled) == Data("controlled".utf8))
        #expect(try Data(contentsOf: unknown) == Data("unknown".utf8))
        #expect(store.snapshot == before)
        try FileManager.default.removeItem(at: unknown)
        #expect(try EchoStore(directory: directory).snapshot == before)
        #expect(!FileManager.default.fileExists(atPath: stage.path))
    }

    @Test func interruptedImportNeverFollowsSymlinksOrDeletesNestedContents() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (_, _, _) = try seeded(directory.appendingPathComponent("Store"))
        let storeDirectory = directory.appendingPathComponent("Store")
        let outside = directory.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let outsideFile = outside.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data("outside".utf8).write(to: outsideFile)
        let linkedStage = storeDirectory.appendingPathComponent("Import-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: linkedStage, withDestinationURL: outside)
        #expect(throws: EchoStoreError.importRecoveryRequiresAttention) { try EchoStore(directory: storeDirectory) }
        #expect(try Data(contentsOf: outsideFile) == Data("outside".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: linkedStage.path) == outside.path)
        try FileManager.default.removeItem(at: linkedStage)
        let stage = storeDirectory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let nested = stage.appendingPathComponent(UUID().uuidString + ".wav", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedFile = nested.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data("nested".utf8).write(to: nestedFile)
        #expect(throws: EchoStoreError.importRecoveryRequiresAttention) { try EchoStore(directory: storeDirectory) }
        #expect(try Data(contentsOf: nestedFile) == Data("nested".utf8))
        try FileManager.default.removeItem(at: nested)
        let link = stage.appendingPathComponent(UUID().uuidString + ".m4a")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)
        #expect(throws: EchoStoreError.importRecoveryRequiresAttention) { try EchoStore(directory: storeDirectory) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == outsideFile.path)
        #expect(try Data(contentsOf: outsideFile) == Data("outside".utf8))
    }

    @Test func interruptedImportCleanupFailureStopsInitialization() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, _) = try seeded(directory)
        let stage = directory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let audio = stage.appendingPathComponent(UUID().uuidString + ".caf")
        try Data("pending".utf8).write(to: audio)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: stage.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path) }
        #expect(throws: EchoStoreError.importRecoveryRequiresAttention) { try EchoStore(directory: directory) }
        #expect(try Data(contentsOf: audio) == Data("pending".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path)
        #expect(try EchoStore(directory: directory).snapshot == store.snapshot)
        #expect(!FileManager.default.fileExists(atPath: stage.path))
    }
}
