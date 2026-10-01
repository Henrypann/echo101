import CryptoKit
import Foundation

struct EchoArchive {
    var format: String = "Echo101"
    var formatVersion: Int = 1
    var schemaVersion: Int = EchoValidation.schemaVersion
    var snapshot: EchoSnapshot
    var audio: [EchoArchiveAudio]
    var wordStars: [String] = []
}

extension EchoArchive: Codable {
    enum CodingKeys: String, CodingKey {
        case format, formatVersion, schemaVersion, snapshot, audio, wordStars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? "Echo101"
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        snapshot = try container.decode(EchoSnapshot.self, forKey: .snapshot)
        audio = try container.decodeIfPresent([EchoArchiveAudio].self, forKey: .audio) ?? []
        wordStars = try container.decodeIfPresent([String].self, forKey: .wordStars) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encode(audio, forKey: .audio)
        try container.encode(wordStars, forKey: .wordStars)
    }
}

struct EchoArchiveAudio: Codable {
    var filename: String
    var byteCount: Int
    var sha256: String
    var data: Data
}

extension EchoStore {
    public func exportArchive(includeAudio: Bool) throws -> URL {
        try markExported()
        var exported = snapshot
        var audio: [EchoArchiveAudio] = []
        if includeAudio {
            var total = 0
            var seen = Set<String>()
            for name in exported.referencedAudioFilenames where seen.insert(name.lowercased()).inserted {
                let data = try boundedRead(audioURL(filename: name), maximum: EchoValidation.maxClipBytes)
                total += data.count
                guard total <= EchoValidation.maxTotalAudioBytes else { throw EchoStoreError.archiveTooLarge }
                audio.append(EchoArchiveAudio(filename: name, byteCount: data.count, sha256: Self.digest(data), data: data))
            }
        } else {
            exported.clips = []
            for index in exported.records.indices {
                exported.records[index].grandparentAudio = nil
                exported.records[index].childAudio = nil
            }
        }
        try EchoValidation.snapshot(exported)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(EchoArchive(snapshot: exported, audio: audio, wordStars: repeatedWordIDs))
        guard data.count <= EchoValidation.maxArchiveBytes else { throw EchoStoreError.archiveTooLarge }
        let exports = directory.appendingPathComponent("Exports", isDirectory: true)
        try prepareDirectory(exports)
        let destination = exports.appendingPathComponent("Echo101-\(UUID().uuidString).echo101")
        try writePrivate(data, to: destination)
        return destination
    }

    public func restoreArchive(fromURL url: URL) throws {
        guard !snapshot.blocksRestore else { throw EchoStoreError.restoreRequiresEmptyStore }
        let data = try boundedRead(url, maximum: EchoValidation.maxArchiveBytes)
        // Inspect version before decoding the potentially large base64 payload.
        guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              header["format"] as? String == "Echo101" else { throw EchoStoreError.corruptArchive }
        guard header["formatVersion"] as? Int == 1,
              let schema = header["schemaVersion"] as? Int,
              (EchoValidation.minimumSchemaVersion...EchoValidation.schemaVersion).contains(schema) else { throw EchoStoreError.unsupportedVersion }
        let archive: EchoArchive
        do { archive = try JSONDecoder().decode(EchoArchive.self, from: data) }
        catch { throw EchoStoreError.corruptArchive }
        let migrated = EchoMigration.migrate(archive.snapshot, from: schema)
        try EchoValidation.snapshot(migrated)
        let referenced = Set(migrated.referencedAudioFilenames.map { $0.lowercased() })
        guard Set(archive.audio.map { $0.filename.lowercased() }) == referenced,
              archive.audio.count == referenced.count else { throw EchoStoreError.corruptArchive }
        var names = Set<String>(), total = 0
        for audio in archive.audio {
            try EchoValidation.filename(audio.filename)
            guard names.insert(audio.filename).inserted, referenced.contains(audio.filename.lowercased()),
                  audio.byteCount > 0, audio.byteCount == audio.data.count,
                  audio.sha256 == Self.digest(audio.data) else { throw EchoStoreError.corruptArchive }
            guard audio.data.count <= EchoValidation.maxClipBytes else { throw EchoStoreError.archiveTooLarge }
            total += audio.data.count
            guard total <= EchoValidation.maxTotalAudioBytes else { throw EchoStoreError.archiveTooLarge }
            _ = try unusedRecordingURL(audio.filename)
        }
        let staging = directory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try prepareDirectory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        var installed: [URL] = []
        do {
            for audio in archive.audio {
                let staged = staging.appendingPathComponent(audio.filename)
                try writePrivate(audio.data, to: staged)
                try safeRegularFile(staged, in: staging)
            }
            for audio in archive.audio {
                let destination = try unusedRecordingURL(audio.filename)
                try FileManager.default.moveItem(at: staging.appendingPathComponent(audio.filename), to: destination)
                installed.append(destination)
            }
            try persist(migrated)
        } catch {
            for installedURL in installed {
                if (try? safeRegularFile(installedURL, in: recordingsDirectory)) != nil {
                    try? FileManager.default.removeItem(at: installedURL)
                }
            }
            throw error
        }
        try? replaceWordStars(archive.wordStars)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
