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
    let context: NSManagedObjectContext
    private let coordinator: NSPersistentStoreCoordinator
    private let fileManager = FileManager.default
    // A transaction fault seam used by synthetic unit tests, never persisted.
    var beforeSave: (() throws -> Void)?
    /// Counts successful full-library encodes. Playback and word stars must not increment this.
    public private(set) var fullStoreSaveCount = 0
    public private(set) var repeatedWordIDs: [String] = []
    private var pendingUsage: [UsageEvent] = []

    public init(directory: URL, inMemory: Bool = false) throws {
        guard directory.isFileURL, !directory.pathComponents.contains("..") else { throw EchoStoreError.unsafeFile }
        // Foundation standardization can rewrite physical /private paths back
        // to aliases. Resolve only OS-owned aliases, not user-created symlinks.
        self.directory = Self.physicalSystemURL(directory)
        temporaryDirectory = self.directory.appendingPathComponent("Temporary", isDirectory: true)
        recordingsDirectory = self.directory.appendingPathComponent("Recordings", isDirectory: true)
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
            try loadStoredState(state)
            for clip in snapshot.clips { _ = try clipURL(for: clip) }
            for record in snapshot.records {
                if let name = record.grandparentAudio { _ = try audioURL(name) }
                if let name = record.childAudio { _ = try audioURL(name) }
            }
        }
        try loadSideFiles()
        try cleanInterruptedImports()
        // Only raw direct-child files in this app-owned folder are removed.
        for url in try fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true && values.isSymbolicLink != true { try fileManager.removeItem(at: url) }
        }
        try cleanOrphanRecordings()
        try clearExports()
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
        let removed = snapshot.clips.filter { expressionIDs.contains($0.expressionID) }
        var next = snapshot
        next.moments.removeAll { $0.id == id }
        next.expressions.removeAll { expressionIDs.contains($0.id) }
        next.clips.removeAll { expressionIDs.contains($0.expressionID) }
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

    /// Updates memory and the small usage log only. It does not encode the whole library.
    public func recordUsage(expressionID: UUID, kind: UsageKind) throws {
        let index = try confirmedIndex(expressionID)
        let event = UsageEvent(expressionID: expressionID, kind: kind)
        var next = snapshot
        next.events.append(event)
        next.events = EchoValidation.cappedEvents(next.events)
        next.expressions[index].lastUsedAt = event.createdAt
        pendingUsage.append(event)
        do { try writeUsageLog() }
        catch { pendingUsage.removeLast(); throw error }
        snapshot = EchoValidation.ordered(next)
    }

    /// Folds the usage log into the library. Call when leaving the app, not on each playback.
    public func flushUsage() throws {
        guard !pendingUsage.isEmpty else { return }
        try persist(snapshot)
    }

    public func markWordRepeated(_ id: String) throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count), !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains("\0") else {
            throw EchoStoreError.invalidData("Invalid word id.")
        }
        guard !repeatedWordIDs.contains(trimmed) else { return }
        repeatedWordIDs.append(trimmed)
        do { try writeStars() }
        catch { repeatedWordIDs.removeAll { $0 == trimmed }; throw error }
    }

    public func rotationPhrases() -> [LibraryPhrase] { snapshot.phrases }

    public func installSeedPhrasesIfEmpty() throws {
        guard snapshot.phrases.isEmpty, snapshot.moments.isEmpty, snapshot.records.isEmpty, snapshot.expressions.isEmpty else { return }
        var next = snapshot
        next.phrases = SeedLibrary.make()
        try persist(next)
    }

    public func setModelConsent(granted: Bool, at date: Date = Date()) throws {
        var next = snapshot
        next.consentGrantedAt = granted ? date : nil
        try persist(next)
    }

    public func setAllowCellular(_ allowed: Bool) throws {
        var next = snapshot
        next.allowCellular = allowed
        try persist(next)
    }

    public func logSetupIssue(code: String, message: String) throws {
        if snapshot.setupIssues.contains(where: { $0.code == code }) { return }
        var next = snapshot
        next.setupIssues.append(SetupIssue(code: code, message: message))
        try persist(next)
    }

    public func resolveSetupIssue(code: String) throws {
        guard snapshot.setupIssues.contains(where: { $0.code == code }) else { return }
        var next = snapshot
        next.setupIssues.removeAll { $0.code == code }
        try persist(next)
    }

    @discardableResult
    public func savePhrase(_ phrase: LibraryPhrase) throws -> LibraryPhrase {
        var next = snapshot
        if let index = next.phrases.firstIndex(where: { $0.id == phrase.id }) {
            next.phrases[index] = phrase
        } else { next.phrases.append(phrase) }
        try persist(next)
        return phrase
    }

    public func deletePhrase(id: UUID) throws {
        guard snapshot.phrases.contains(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        var next = snapshot
        next.phrases.removeAll { $0.id == id }
        for index in next.records.indices where next.records[index].phraseID == id {
            next.records[index].phraseID = nil
        }
        try persist(next)
    }

    @discardableResult
    public func addSpokenRecord(_ record: SpokenRecord, audioTemporaryURL: URL? = nil) throws -> SpokenRecord {
        var record = record
        var created: String?
        if let audioTemporaryURL {
            created = try importAudio(from: audioTemporaryURL)
            record.grandparentAudio = created
        }
        var next = snapshot
        if let index = next.records.firstIndex(where: { $0.id == record.id }) { next.records[index] = record }
        else { next.records.append(record) }
        do { try persist(next) }
        catch {
            if let created { try? removeAudioFile(created) }
            throw error
        }
        if let audioTemporaryURL { try? fileManager.removeItem(at: audioTemporaryURL) }
        return record
    }

    public func updateSpokenRecord(_ record: SpokenRecord) throws {
        guard snapshot.records.contains(where: { $0.id == record.id }) else { throw EchoStoreError.notFound }
        var next = snapshot
        guard let index = next.records.firstIndex(where: { $0.id == record.id }) else { throw EchoStoreError.notFound }
        next.records[index] = record
        try persist(next)
    }

    /// Parent confirmation is the only way a generated sentence joins the library.
    @discardableResult
    public func confirmSpokenRecord(id: UUID, english: String, chinese: String) throws -> LibraryPhrase {
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        let phrase = LibraryPhrase(chinese: chinese, english: english, keywords: [chinese], source: "parent")
        var next = snapshot
        next.phrases.append(phrase)
        next.records[index].english = english
        next.records[index].chineseMeaning = chinese
        next.records[index].kind = .confirmed
        next.records[index].phraseID = phrase.id
        try persist(next)
        return phrase
    }

    @discardableResult
    public func attachChildAudio(recordID: UUID, temporaryURL: URL) throws -> SpokenRecord {
        guard let index = snapshot.records.firstIndex(where: { $0.id == recordID }) else { throw EchoStoreError.notFound }
        let filename = try importAudio(from: temporaryURL)
        var next = snapshot
        let previous = next.records[index].childAudio
        next.records[index].childAudio = filename
        do { try persist(next) }
        catch { try? removeAudioFile(filename); throw error }
        if let previous { try? removeAudioFile(previous) }
        try? fileManager.removeItem(at: temporaryURL)
        return snapshot.records.first(where: { $0.id == recordID }) ?? next.records[index]
    }

    public func deleteSpokenRecord(id: UUID) throws {
        guard let record = snapshot.records.first(where: { $0.id == id }) else { throw EchoStoreError.notFound }
        var next = snapshot
        next.records.removeAll { $0.id == id }
        try persist(next)
        for name in [record.grandparentAudio, record.childAudio].compactMap({ $0 }) {
            try? removeAudioFile(name)
        }
    }

    public func eraseFamilyData() throws {
        let names = snapshot.referencedAudioFilenames
        try persist(EchoSnapshot())
        for name in names { try? removeAudioFile(name) }
    }

    public func discardExport(at url: URL) throws {
        let exports = directory.appendingPathComponent("Exports", isDirectory: true)
        try safeRegularFile(url, in: exports)
        guard url.pathExtension.lowercased() == "echo101" else { throw EchoStoreError.unsafeFile }
        try fileManager.removeItem(at: url)
    }

    func markExported(at date: Date = Date()) throws {
        var next = snapshot
        next.lastExportAt = date
        try persist(next)
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

    public func clipURL(for clip: VoiceClip) throws -> URL {
        guard snapshot.clips.contains(clip) else { throw EchoStoreError.notFound }
        try EchoValidation.filename(clip.filename)
        let url = recordingsDirectory.appendingPathComponent(clip.filename)
        try safeRegularFile(url, in: recordingsDirectory)
        return url
    }

    func persist(_ proposed: EchoSnapshot) throws {
        var proposed = proposed
        proposed.events = EchoValidation.cappedEvents(proposed.events)
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
        fullStoreSaveCount += 1
        pendingUsage = []
        try? removeSideFile(usageLogURL)
    }

    private var usageLogURL: URL { directory.appendingPathComponent("UsageLog.json") }
    private var starsURL: URL { directory.appendingPathComponent("WordStars.json") }

    private func loadStoredState(_ state: NSManagedObject) throws {
        guard state.value(forKey: "key") as? String == "library",
              let version = Self.intValue(state.value(forKey: "version")),
              let payload = state.value(forKey: "payload") as? Data else { throw EchoStoreError.unsupportedVersion }
        guard (EchoValidation.minimumSchemaVersion...EchoValidation.schemaVersion).contains(version) else {
            throw EchoStoreError.unsupportedVersion
        }
        let decoded: EchoSnapshot
        do { decoded = try JSONDecoder().decode(EchoSnapshot.self, from: payload) }
        catch { throw EchoStoreError.invalidData("The library could not be read.") }
        var loaded = EchoMigration.migrate(decoded, from: version)
        try applyUsageLog(to: &loaded)
        if version < EchoValidation.schemaVersion {
            try persist(loaded)
        } else {
            try EchoValidation.snapshot(loaded)
            snapshot = EchoValidation.ordered(loaded)
        }
    }

    private func applyUsageLog(to snapshot: inout EchoSnapshot) throws {
        let logged = try readUsageLog()
        guard !logged.isEmpty else { return }
        let known = Set(snapshot.events.map(\.id))
        let fresh = logged.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for event in fresh {
            guard let index = snapshot.expressions.firstIndex(where: { $0.id == event.expressionID && $0.isConfirmed }) else { continue }
            snapshot.events.append(event)
            if snapshot.expressions[index].lastUsedAt == nil || event.createdAt > snapshot.expressions[index].lastUsedAt! {
                snapshot.expressions[index].lastUsedAt = event.createdAt
            }
            pendingUsage.append(event)
        }
        snapshot.events = EchoValidation.cappedEvents(snapshot.events)
    }

    private func loadSideFiles() throws {
        if FileManager.default.fileExists(atPath: starsURL.path) {
            let data = try boundedRead(starsURL, maximum: 512 * 1_024)
            repeatedWordIDs = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        if pendingUsage.isEmpty, FileManager.default.fileExists(atPath: usageLogURL.path) {
            pendingUsage = try readUsageLog()
        }
    }

    private func readUsageLog() throws -> [UsageEvent] {
        guard fileManager.fileExists(atPath: usageLogURL.path) else { return [] }
        let data = try boundedRead(usageLogURL, maximum: 8 * 1_024 * 1_024)
        if data.isEmpty { return [] }
        return (try? JSONDecoder().decode([UsageEvent].self, from: data)) ?? []
    }

    private func writeUsageLog() throws {
        let data = try JSONEncoder().encode(pendingUsage)
        try writeReplacing(data, to: usageLogURL)
    }

    private func writeStars() throws {
        let data = try JSONEncoder().encode(repeatedWordIDs)
        try writeReplacing(data, to: starsURL)
    }

    func replaceWordStars(_ ids: [String]) throws {
        repeatedWordIDs = ids
        try writeStars()
    }

    private func writeReplacing(_ data: Data, to url: URL) throws {
        try rejectSymlink(url)
        let temporary = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try writePrivate(data, to: temporary)
        if fileManager.fileExists(atPath: url.path) {
            try safeRegularFile(url, in: directory)
            try fileManager.removeItem(at: url)
        }
        try rejectSymlink(url)
        try fileManager.moveItem(at: temporary, to: url)
    }

    private func removeSideFile(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try safeRegularFile(url, in: directory)
        try fileManager.removeItem(at: url)
    }

    private func clearExports() throws {
        let exports = directory.appendingPathComponent("Exports", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: exports.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        try rejectSymlinkComponents(exports)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        for url in try fileManager.contentsOfDirectory(at: exports, includingPropertiesForKeys: Array(keys)) {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try safeRegularFile(url, in: exports)
            try fileManager.removeItem(at: url)
        }
    }

    func importAudio(from temporaryURL: URL) throws -> String {
        try safeRegularFile(temporaryURL, in: temporaryDirectory)
        let ext = temporaryURL.pathExtension.lowercased()
        guard EchoValidation.allowedExtensions.contains(ext) else { throw EchoStoreError.unsafeFile }
        let data = try boundedRead(temporaryURL, maximum: EchoValidation.maxClipBytes)
        guard !data.isEmpty else { throw EchoStoreError.invalidData("Empty recording.") }
        let filename = UUID().uuidString + "." + ext
        let destination = try unusedRecordingURL(filename)
        try writePrivate(data, to: destination)
        return filename
    }

    public func audioURL(filename: String) throws -> URL {
        try EchoValidation.filename(filename)
        let url = recordingsDirectory.appendingPathComponent(filename)
        try safeRegularFile(url, in: recordingsDirectory)
        return url
    }

    func removeAudioFile(_ filename: String) throws {
        try EchoValidation.filename(filename)
        let url = recordingsDirectory.appendingPathComponent(filename)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fileManager.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw EchoStoreError.unsafeFile }
        try safeRegularFile(url, in: recordingsDirectory)
        try fileManager.removeItem(at: url)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let number = value as? NSNumber { return number.intValue }
        return nil
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
        let referenced = Set(snapshot.referencedAudioFilenames.map { $0.lowercased() })
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
