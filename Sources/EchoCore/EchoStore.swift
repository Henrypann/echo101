import Combine
import CoreData
import Darwin
import Foundation

@MainActor
public final class EchoStore: ObservableObject {
    @Published public private(set) var snapshot: EchoSnapshot
    public let directory: URL
    public let temporaryDirectory: URL
    public let recordingsDirectory: URL
    public let exportsDirectory: URL
    let context: NSManagedObjectContext
    private let coordinator: NSPersistentStoreCoordinator
    private let fileManager = FileManager.default
    private let usageOverlayURL: URL
    /// Counts full-library encodes. Playback updates an overlay file and does not increment this.
    public private(set) var fullSaveCount = 0
    // A transaction fault seam used by synthetic unit tests, never persisted.
    var beforeSave: (() throws -> Void)?

    public init(directory: URL, inMemory: Bool = false) throws {
        guard directory.isFileURL, !directory.pathComponents.contains("..") else { throw EchoStoreError.unsafeFile }
        // Foundation standardization can rewrite physical /private paths back
        // to aliases. Resolve only OS-owned aliases, not user-created symlinks.
        self.directory = Self.physicalSystemURL(directory)
        temporaryDirectory = self.directory.appendingPathComponent("Temporary", isDirectory: true)
        recordingsDirectory = self.directory.appendingPathComponent("Recordings", isDirectory: true)
        exportsDirectory = self.directory.appendingPathComponent("Exports", isDirectory: true)
        usageOverlayURL = self.directory.appendingPathComponent("UsageOverlay.json")
        snapshot = EchoSnapshot()
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "EchoState"
        entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let result = NSAttributeDescription()
            result.name = name; result.attributeType = type; result.isOptional = false
            return result
        }
        entity.properties = [attribute("key", .stringAttributeType), attribute("version", .integer64AttributeType), attribute("payload", .binaryDataAttributeType)]
        entity.uniquenessConstraints = [["key"]]
        model.entities = [entity]
        model.versionIdentifiers = ["Echo101-v1"]
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        try prepareDirectory(self.directory)
        try prepareDirectory(temporaryDirectory)
        try prepareDirectory(recordingsDirectory)
        let storeURL = self.directory.appendingPathComponent("Echo101.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try rejectSymlink(URL(fileURLWithPath: storeURL.path + suffix))
        }
        var options: [AnyHashable: Any] = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        #if os(iOS)
        options[NSPersistentStoreFileProtectionKey] = FileProtectionType.complete
        #endif
        try coordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType,
                                           configurationName: nil, at: inMemory ? nil : storeURL, options: options)
        let states = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "EchoState"))
        guard states.count <= 1 else { throw EchoStoreError.invalidData("Multiple library states.") }
        if let state = states.first {
            let rawVersion = state.value(forKey: "version")
            let storedVersion = rawVersion as? Int ?? (rawVersion as? NSNumber)?.intValue
            guard state.value(forKey: "key") as? String == "library",
                  let storedVersion,
                  let payload = state.value(forKey: "payload") as? Data else { throw EchoStoreError.unsupportedVersion }
            guard storedVersion >= EchoValidation.minimumSchemaVersion,
                  storedVersion <= EchoValidation.schemaVersion else { throw EchoStoreError.unsupportedVersion }
            let loaded = try EchoMigration.snapshot(from: payload, storedVersion: storedVersion)
            try EchoValidation.snapshot(loaded)
            snapshot = EchoValidation.ordered(loaded)
            for clip in snapshot.clips { _ = try clipURL(for: clip) }
            applyUsageOverlay()
            if storedVersion < EchoValidation.schemaVersion {
                try persist(snapshot)
            }
        } else {
            applyUsageOverlay()
        }
        try clearExports()
        try cleanInterruptedImports()
        // Only raw direct-child files in this app-owned folder are removed.
        for url in try fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true && values.isSymbolicLink != true { try fileManager.removeItem(at: url) }
        }
        try cleanOrphanRecordings()
    }

    @discardableResult
    public func createMoment(scene: String, note: String) throws -> Moment {
        let moment = Moment(scene: scene, note: note)
        var next = snapshot; next.moments.append(moment)
        try persist(next); return moment
    }

    public func updateMoment(_ moment: Moment) throws {
        guard let index = snapshot.moments.firstIndex(where: { $0.id == moment.id }) else { throw EchoStoreError.notFound }
        var next = snapshot; next.moments[index] = moment; try persist(next)
    }

    public func deleteMoment(id: UUID) throws {
        guard snapshot.moments.contains(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        let expressionIDs = Set(snapshot.expressions.filter { $0.momentID == id }.map(\.id))
        let removed = snapshot.clips.filter { clip in
            guard let expressionID = clip.expressionID else { return false }
            return expressionIDs.contains(expressionID)
        }
        var next = snapshot
        next.moments.removeAll { $0.id == id }
        next.expressions.removeAll { expressionIDs.contains($0.id) }
        next.clips.removeAll { clip in
            guard let expressionID = clip.expressionID else { return false }
            return expressionIDs.contains(expressionID)
        }
        next.events.removeAll { expressionIDs.contains($0.expressionID) }
        try persist(next); try removeRecordings(removed)
    }

    public func saveExpression(_ expression: Expression) throws {
        try saveExpressions([expression])
    }

    public func saveExpressions(_ expressions: [Expression]) throws {
        guard Set(expressions.map(\.id)).count == expressions.count else {
            throw EchoStoreError.invalidData("Duplicate identifiers in expression batch.")
        }
        guard !expressions.isEmpty else { return }
        var next = snapshot
        for expression in expressions {
            if let index = next.expressions.firstIndex(where: { $0.id == expression.id }) {
                next.expressions[index] = expression
            } else { next.expressions.append(expression) }
        }
        try persist(next)
    }

    public func deleteExpression(id: UUID) throws {
        guard snapshot.expressions.contains(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        let removed = snapshot.clips.filter { $0.expressionID == id }
        var next = snapshot
        next.expressions.removeAll { $0.id == id }
        next.clips.removeAll { $0.expressionID == id }
        next.events.removeAll { $0.expressionID == id }
        try persist(next); try removeRecordings(removed)
    }

    public func toggleFavorite(id: UUID) throws {
        let index = try confirmedIndex(id)
        var next = snapshot
        next.expressions[index].isFavorite.toggle()
        if next.expressions[index].isFavorite {
            next.events.append(UsageEvent(expressionID: id, kind: .favorite))
        }
        try persist(next)
    }

    /// Records a play without encoding the whole library. The overlay is merged on the next launch and flushed on background.
    public func recordUsage(expressionID: UUID, kind: UsageKind, at date: Date = Date()) throws {
        try rememberUsage(expressionID: expressionID, kind: kind, at: date)
    }

    public func flushUsage() throws {
        guard fileManager.fileExists(atPath: usageOverlayURL.path) else { return }
        try persist(snapshot)
    }

    @discardableResult
    public func addVoiceClip(expressionID: UUID, temporaryURL: URL) throws -> VoiceClip {
        _ = try confirmedIndex(expressionID)
        try safeRegularFile(temporaryURL, in: temporaryDirectory)
        let ext = temporaryURL.pathExtension.lowercased()
        guard EchoValidation.allowedExtensions.contains(ext) else { throw EchoStoreError.unsafeFile }
        let data = try boundedRead(temporaryURL, maximum: EchoValidation.maxClipBytes)
        guard !data.isEmpty else { throw EchoStoreError.invalidData("Empty recording.") }
        let clip = VoiceClip(expressionID: expressionID, filename: UUID().uuidString + "." + ext)
        let destination = try unusedRecordingURL(clip.filename)
        try writePrivate(data, to: destination)
        do {
            var next = snapshot; next.clips.append(clip); try persist(next)
        } catch {
            try? fileManager.removeItem(at: destination); throw error
        }
        try? fileManager.removeItem(at: temporaryURL)
        return clip
    }

    public func deleteClip(id: UUID) throws {
        guard let clip = snapshot.clips.first(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        var next = snapshot; next.clips.removeAll { $0.id == id }
        try persist(next); try removeRecordings([clip])
    }

    public func saveRecord(_ record: SpeechRecord) throws {
        var next = snapshot
        if let index = next.records.firstIndex(where: { $0.id == record.id }) {
            next.records[index] = record
        } else {
            next.records.append(record)
        }
        try persist(next)
    }

    /// Parent confirmation is the only way a generated or pending line joins the library.
    @discardableResult
    public func confirmRecord(id: UUID, english: String, chinese: String, scene: String) throws -> LibraryPhrase {
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        var record = snapshot.records[index]
        guard record.needsConfirmation else { throw EchoStoreError.invalidData("This line is already confirmed.") }
        var keywords: [String] = []
        let alias = record.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if (2...80).contains(alias.count) { keywords = [alias] }
        let phrase = LibraryPhrase(english: english, chinese: chinese, scene: scene, keywords: keywords, source: "parent")
        record.english = english
        record.chinese = chinese
        record.scene = scene
        record.needsConfirmation = false
        record.origin = "library"
        record.phraseID = phrase.id
        var next = snapshot
        next.library.append(phrase)
        next.records[index] = record
        try persist(next)
        return phrase
    }

    public func addLibraryPhrase(_ phrase: LibraryPhrase) throws {
        var next = snapshot
        guard !next.library.contains(where: { $0.id == phrase.id }) else {
            throw EchoStoreError.invalidData("Duplicate phrase.")
        }
        next.library.append(phrase)
        try persist(next)
    }

    public func updateLibraryPhrase(_ phrase: LibraryPhrase) throws {
        guard let index = snapshot.library.firstIndex(where: { $0.id == phrase.id }) else { throw EchoStoreError.notFound }
        var next = snapshot
        var edited = phrase
        if next.library[index].source == "seed" && edited.source == "seed" { edited.source = "parent" }
        next.library[index] = edited
        for recordIndex in next.records.indices where next.records[recordIndex].phraseID == phrase.id && next.records[recordIndex].origin == "library" {
            next.records[recordIndex].english = edited.english
            next.records[recordIndex].chinese = edited.chinese
            next.records[recordIndex].scene = edited.scene
        }
        try persist(next)
    }

    public func deleteLibraryPhrase(id: UUID) throws {
        guard snapshot.library.contains(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        var next = snapshot
        next.library.removeAll { $0.id == id }
        let stillConfirmed = next.expressions.contains { $0.id == id && $0.isConfirmed }
        if !stillConfirmed {
            next.events.removeAll { $0.expressionID == id }
        }
        for index in next.records.indices where next.records[index].phraseID == id {
            next.records[index].phraseID = nil
            next.records[index].origin = "archived"
            next.records[index].needsConfirmation = false
        }
        try persist(next)
    }

    public func installSeedLibrary() throws {
        var next = snapshot
        let existing = Set(next.library.map { $0.english.lowercased() })
        for phrase in SeedLibrary.phrases where !existing.contains(phrase.english.lowercased()) {
            next.library.append(phrase)
        }
        guard next.library.count != snapshot.library.count else { return }
        try persist(next)
    }

    public func updateSettings(_ change: (inout EchoSettings) -> Void) throws {
        var next = snapshot
        change(&next.settings)
        try persist(next)
    }

    public func markExported(at date: Date = Date()) throws {
        try updateSettings { $0.lastExportAt = date }
    }

    public func deleteAllContent() throws {
        let removed = snapshot.clips
        try persist(EchoSnapshot())
        try removeRecordings(removed)
    }

    @discardableResult
    public func addRecordRecording(recordID: UUID, role: String, temporaryURL: URL) throws -> VoiceClip {
        guard snapshot.records.contains(where: { $0.id == recordID }) else { throw EchoStoreError.notFound }
        guard role == "grandparent" || role == "child" else { throw EchoStoreError.invalidData("Unknown recording role.") }
        try safeRegularFile(temporaryURL, in: temporaryDirectory)
        let ext = temporaryURL.pathExtension.lowercased()
        guard EchoValidation.allowedExtensions.contains(ext) else { throw EchoStoreError.unsafeFile }
        let data = try boundedRead(temporaryURL, maximum: EchoValidation.maxClipBytes)
        guard !data.isEmpty else { throw EchoStoreError.invalidData("Empty recording.") }
        let clip = VoiceClip(filename: UUID().uuidString + "." + ext, recordID: recordID, role: role)
        let destination = try unusedRecordingURL(clip.filename)
        try writePrivate(data, to: destination)
        do {
            var next = snapshot
            next.clips.append(clip)
            try persist(next)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        try? fileManager.removeItem(at: temporaryURL)
        return clip
    }

    public func deleteRecord(id: UUID) throws {
        guard snapshot.records.contains(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        let removed = snapshot.clips.filter { $0.recordID == id }
        var next = snapshot
        next.records.removeAll { $0.id == id }
        next.clips.removeAll { $0.recordID == id }
        try persist(next)
        try removeRecordings(removed)
    }

    /// Deletes one export copy. Only a regular file directly inside Exports/ is accepted.
    public func removeExportFile(at url: URL) throws {
        try safeRegularFile(url, in: exportsDirectory)
        guard url.pathExtension.lowercased() == "echo101" else { throw EchoStoreError.unsafeFile }
        try fileManager.removeItem(at: url)
    }

    public func clipURL(for clip: VoiceClip) throws -> URL {
        guard snapshot.clips.contains(clip) else { throw EchoStoreError.notFound }
        try EchoValidation.filename(clip.filename)
        let url = recordingsDirectory.appendingPathComponent(clip.filename)
        try safeRegularFile(url, in: recordingsDirectory)
        return url
    }

    func persist(_ proposed: EchoSnapshot) throws {
        var proposed = proposed
        let others = proposed.moments.count + proposed.expressions.count + proposed.clips.count
            + proposed.library.count + proposed.records.count
        proposed.events = EchoValidation.cappedEvents(proposed.events, otherRecords: others)
        try EchoValidation.snapshot(proposed)
        let next = EchoValidation.ordered(proposed)
        let payload = try JSONEncoder().encode(next)
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "EchoState")
            let state = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "EchoState", into: context)
            state.setValue("library", forKey: "key")
            state.setValue(EchoValidation.schemaVersion, forKey: "version")
            state.setValue(payload, forKey: "payload")
            try beforeSave?()
            try context.save()
        } catch { context.rollback(); throw error }
        snapshot = next
        fullSaveCount += 1
        removeUsageOverlay()
    }

    private struct UsageOverlay: Codable {
        var events: [UsageEvent]
        var lastUsed: [String: Date]
    }

    private func rememberUsage(expressionID: UUID, kind: UsageKind, at date: Date) throws {
        let confirmedExpression = snapshot.expressions.contains { $0.id == expressionID && $0.isConfirmed }
        let inLibrary = snapshot.library.contains { $0.id == expressionID }
        if snapshot.expressions.contains(where: { $0.id == expressionID }) {
            guard confirmedExpression else { throw EchoStoreError.confirmationRequired }
        } else if !inLibrary {
            throw EchoStoreError.notFound
        }
        guard date.timeIntervalSince1970.isFinite else { throw EchoStoreError.invalidData("Invalid date.") }
        var next = snapshot
        let calendar = Calendar.current
        if let index = next.events.firstIndex(where: {
            $0.expressionID == expressionID && $0.kind == kind && calendar.isDate($0.createdAt, inSameDayAs: date)
        }) {
            if next.events[index].count < 100_000 { next.events[index].count += 1 }
            if date > next.events[index].createdAt { next.events[index].createdAt = date }
        } else {
            next.events.append(UsageEvent(expressionID: expressionID, createdAt: date, kind: kind, count: 1))
        }
        if let index = next.expressions.firstIndex(where: { $0.id == expressionID }) {
            let current = next.expressions[index].lastUsedAt ?? .distantPast
            if date > current { next.expressions[index].lastUsedAt = date }
        }
        if let index = next.library.firstIndex(where: { $0.id == expressionID }) {
            let current = next.library[index].lastUsedAt ?? .distantPast
            if date > current { next.library[index].lastUsedAt = date }
        }
        let others = next.moments.count + next.expressions.count + next.clips.count + next.library.count + next.records.count
        next.events = EchoValidation.cappedEvents(next.events, otherRecords: others)
        next = EchoValidation.ordered(next)
        var lastUsed: [String: Date] = [:]
        for expression in next.expressions {
            if let used = expression.lastUsedAt { lastUsed[expression.id.uuidString] = used }
        }
        for phrase in next.library {
            if let used = phrase.lastUsedAt { lastUsed[phrase.id.uuidString] = used }
        }
        try writeUsageOverlay(UsageOverlay(events: next.events, lastUsed: lastUsed))
        snapshot = next
    }

    private func writeUsageOverlay(_ overlay: UsageOverlay) throws {
        try rejectSymlinkComponents(directory)
        try rejectSymlink(usageOverlayURL)
        let data = try JSONEncoder().encode(overlay)
        let temp = temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        try writePrivate(data, to: temp)
        if fileManager.fileExists(atPath: usageOverlayURL.path) {
            try rejectSymlink(usageOverlayURL)
            try fileManager.removeItem(at: usageOverlayURL)
        }
        try fileManager.moveItem(at: temp, to: usageOverlayURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: usageOverlayURL.path)
    }

    private func applyUsageOverlay() {
        guard let overlay = readUsageOverlay() else { return }
        var next = snapshot
        var byID: [UUID: UsageEvent] = [:]
        for event in next.events { byID[event.id] = event }
        for event in overlay.events {
            if var existing = byID[event.id] {
                existing.count = max(existing.count, event.count)
                if event.createdAt > existing.createdAt { existing.createdAt = event.createdAt }
                byID[event.id] = existing
            } else {
                byID[event.id] = event
            }
        }
        let expressionIDs = Set(next.expressions.filter(\.isConfirmed).map(\.id))
        let libraryIDs = Set(next.library.map(\.id))
        next.events = byID.values.filter { expressionIDs.contains($0.expressionID) || libraryIDs.contains($0.expressionID) }
        let others = next.moments.count + next.expressions.count + next.clips.count + next.library.count + next.records.count
        next.events = EchoValidation.cappedEvents(next.events, otherRecords: others)
        for (key, date) in overlay.lastUsed {
            guard let id = UUID(uuidString: key) else { continue }
            if let index = next.expressions.firstIndex(where: { $0.id == id }) {
                let current = next.expressions[index].lastUsedAt ?? .distantPast
                if date > current { next.expressions[index].lastUsedAt = date }
            }
            if let index = next.library.firstIndex(where: { $0.id == id }) {
                let current = next.library[index].lastUsedAt ?? .distantPast
                if date > current { next.library[index].lastUsedAt = date }
            }
        }
        snapshot = EchoValidation.ordered(next)
    }

    private func readUsageOverlay() -> UsageOverlay? {
        guard fileManager.fileExists(atPath: usageOverlayURL.path) else { return nil }
        guard (try? safeRegularFile(usageOverlayURL, in: directory)) != nil else { return nil }
        guard let data = try? Data(contentsOf: usageOverlayURL), data.count < 2_000_000 else { return nil }
        return try? JSONDecoder().decode(UsageOverlay.self, from: data)
    }

    private func removeUsageOverlay() {
        guard fileManager.fileExists(atPath: usageOverlayURL.path) else { return }
        guard (try? safeRegularFile(usageOverlayURL, in: directory)) != nil else { return }
        try? fileManager.removeItem(at: usageOverlayURL)
    }

    private func clearExports() throws {
        guard fileManager.fileExists(atPath: exportsDirectory.path) else { return }
        let values = try exportsDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { return }
        try rejectSymlink(exportsDirectory)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        for url in try fileManager.contentsOfDirectory(at: exportsDirectory, includingPropertiesForKeys: Array(keys)) {
            let item = try url.resourceValues(forKeys: keys)
            guard item.isRegularFile == true, item.isSymbolicLink != true else { continue }
            try safeRegularFile(url, in: exportsDirectory)
            try fileManager.removeItem(at: url)
        }
    }

    private func confirmedIndex(_ id: UUID) throws -> Int {
        guard let index = snapshot.expressions.firstIndex(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        guard snapshot.expressions[index].isConfirmed else { throw EchoStoreError.confirmationRequired }
        return index
    }

    func prepareDirectory(_ url: URL) throws {
        try rejectSymlinkComponents(url)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw EchoStoreError.unsafeFile }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        #endif
    }

    func rejectSymlink(_ url: URL) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else { throw EchoStoreError.unsafeFile }
    }

    func rejectSymlinkComponents(_ url: URL) throws {
        var cursor = Self.physicalSystemURL(url)
        while cursor.path != "/" {
            try rejectSymlink(cursor)
            cursor.deleteLastPathComponent()
        }
    }

    func safeRegularFile(_ url: URL, in parent: URL? = nil) throws {
        guard url.isFileURL, !url.pathComponents.contains("..") else { throw EchoStoreError.unsafeFile }
        if let parent {
            guard Self.physicalSystemURL(url).deletingLastPathComponent().path == Self.physicalSystemURL(parent).path else { throw EchoStoreError.unsafeFile }
        }
        try rejectSymlinkComponents(url)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw EchoStoreError.unsafeFile }
    }

    func boundedRead(_ url: URL, maximum: Int) throws -> Data {
        try safeRegularFile(url)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= Int64(maximum) else { throw EchoStoreError.archiveTooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw EchoStoreError.archiveTooLarge }
        return data
    }

    func unusedRecordingURL(_ filename: String) throws -> URL {
        try EchoValidation.filename(filename)
        try rejectSymlinkComponents(recordingsDirectory)
        let url = recordingsDirectory.appendingPathComponent(filename)
        try rejectSymlink(url)
        guard !fileManager.fileExists(atPath: url.path) else { throw EchoStoreError.unsafeFile }
        return url
    }

    func writePrivate(_ data: Data, to url: URL) throws {
        try rejectSymlinkComponents(url)
        #if os(iOS)
        try data.write(to: url, options: [.withoutOverwriting, .completeFileProtection])
        #else
        try data.write(to: url, options: [.withoutOverwriting])
        #endif
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }

    private func removeRecordings(_ clips: [VoiceClip]) throws {
        var incomplete = false
        for clip in clips {
            do {
                try EchoValidation.filename(clip.filename)
                let url = recordingsDirectory.appendingPathComponent(clip.filename)
                // Missing files already satisfy deletion; symlinks (including
                // dangling ones) remain untouched and are explicitly reported.
                let attributes: [FileAttributeKey: Any]
                do { attributes = try fileManager.attributesOfItem(atPath: url.path) }
                catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { continue }
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw EchoStoreError.unsafeFile }
                try safeRegularFile(url, in: recordingsDirectory)
                try fileManager.removeItem(at: url)
            } catch { incomplete = true }
        }
        if incomplete { throw EchoStoreError.recordingCleanupIncomplete }
    }

    private func cleanOrphanRecordings() throws {
        let referenced = Set(snapshot.clips.map { $0.filename.lowercased() })
        try rejectSymlinkComponents(recordingsDirectory)
        for url in try fileManager.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (try? EchoValidation.filename(url.lastPathComponent)) != nil,
                  !referenced.contains(url.lastPathComponent.lowercased()) else { continue }
            // No recursive deletion: only controlled direct-child regular files.
            try safeRegularFile(url, in: recordingsDirectory)
            try fileManager.removeItem(at: url)
        }
    }

    private func cleanInterruptedImports() throws {
        var recoverable: [(directory: URL, files: [URL])] = []
        try rejectSymlinkComponents(directory)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for stage in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
            let name = stage.lastPathComponent
            guard name.hasPrefix("Import-") else { continue }
            let suffix = String(name.dropFirst("Import-".count))
            guard suffix.count == 36, let id = UUID(uuidString: suffix),
                  id.uuidString.caseInsensitiveCompare(suffix) == .orderedSame else { continue }
            let values = try stage.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw EchoStoreError.importRecoveryRequiresAttention
            }
            try rejectSymlinkComponents(stage)
            let files = try fileManager.contentsOfDirectory(at: stage, includingPropertiesForKeys: Array(keys))
            // Validate the entire directory before deleting any of its content.
            for file in files {
                let attributes = try file.resourceValues(forKeys: keys)
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                      (try? EchoValidation.filename(file.lastPathComponent)) != nil else {
                    throw EchoStoreError.importRecoveryRequiresAttention
                }
                try safeRegularFile(file, in: stage)
            }
            recoverable.append((stage, files))
        }
        for stage in recoverable {
            do {
                for file in stage.files {
                    try safeRegularFile(file, in: stage.directory)
                    // unlink and rmdir cannot recursively delete a replaced
                    // directory or newly introduced unknown nested content.
                    guard Darwin.unlink(file.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                }
                try rejectSymlinkComponents(stage.directory)
                guard Darwin.rmdir(stage.directory.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            } catch { throw EchoStoreError.importRecoveryRequiresAttention }
        }
    }

    private static func physicalSystemURL(_ url: URL) -> URL {
        for alias in ["/var", "/tmp"] {
            if url.path == alias || url.path.hasPrefix(alias + "/") {
                return URL(fileURLWithPath: "/private" + url.path, isDirectory: url.hasDirectoryPath)
            }
        }
        return url
    }
}
