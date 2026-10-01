import CryptoKit
import Foundation

struct EchoArchive: Codable {
    var format: String = "Echo101"
    var formatVersion: Int = 1
    var schemaVersion: Int = EchoValidation.schemaVersion
    var snapshot: EchoSnapshot
    var audio: [EchoArchiveAudio]
}

struct ArchiveAudioList: Decodable {
    var audio: [EchoArchiveAudio]
}

struct EchoArchiveAudio: Codable {
    var filename: String
    var byteCount: Int
    var sha256: String
    var data: Data
}

extension EchoStore {
    public func exportArchive(includeAudio: Bool) throws -> URL {
        var exported = snapshot
        var audio: [EchoArchiveAudio] = []
        if includeAudio {
            var total = 0
            for clip in exported.clips {
                let data = try boundedRead(clipURL(for: clip), maximum: EchoValidation.maxClipBytes)
                total += data.count
                guard total <= EchoValidation.maxTotalAudioBytes else { throw EchoStoreError.archiveTooLarge }
                audio.append(EchoArchiveAudio(filename: clip.filename, byteCount: data.count, sha256: Self.digest(data), data: data))
            }
        } else { exported.clips = [] }
        try EchoValidation.snapshot(exported)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(EchoArchive(snapshot: exported, audio: audio))
        guard data.count <= EchoValidation.maxArchiveBytes else { throw EchoStoreError.archiveTooLarge }
        let exports = directory.appendingPathComponent("Exports", isDirectory: true)
        try prepareDirectory(exports)
        let destination = exports.appendingPathComponent("Echo101-\(UUID().uuidString).echo101")
        try writePrivate(data, to: destination)
        return destination
    }

    public func restoreArchive(fromURL url: URL) throws {
        guard snapshot.isEmpty || snapshot.isPristineSeededLibrary else { throw EchoStoreError.restoreRequiresEmptyStore }
        let data = try boundedRead(url, maximum: EchoValidation.maxArchiveBytes)
        // Inspect version before decoding the potentially large base64 payload.
        guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              header["format"] as? String == "Echo101" else { throw EchoStoreError.corruptArchive }
        guard header["formatVersion"] as? Int == 1,
              let schemaVersion = header["schemaVersion"] as? Int,
              schemaVersion >= EchoValidation.minimumSchemaVersion,
              schemaVersion <= EchoValidation.schemaVersion else { throw EchoStoreError.unsupportedVersion }
        let archive: EchoArchive
        if schemaVersion == EchoValidation.schemaVersion {
            do { archive = try JSONDecoder().decode(EchoArchive.self, from: data) }
            catch { throw EchoStoreError.corruptArchive }
        } else {
            guard let snapshotObject = header["snapshot"] else { throw EchoStoreError.corruptArchive }
            let snapshotData: Data
            do { snapshotData = try JSONSerialization.data(withJSONObject: snapshotObject) }
            catch { throw EchoStoreError.corruptArchive }
            let migrated: EchoSnapshot
            do { migrated = try EchoMigration.snapshot(from: snapshotData, storedVersion: schemaVersion) }
            catch let error as EchoStoreError { throw error }
            catch { throw EchoStoreError.corruptArchive }
            let audio: [EchoArchiveAudio]
            do { audio = try JSONDecoder().decode(ArchiveAudioList.self, from: data).audio }
            catch { throw EchoStoreError.corruptArchive }
            archive = EchoArchive(snapshot: migrated, audio: audio)
        }
        try EchoValidation.snapshot(archive.snapshot)
        guard archive.audio.count == archive.snapshot.clips.count else { throw EchoStoreError.corruptArchive }
        let clipNames = Set(archive.snapshot.clips.map(\.filename))
        var names = Set<String>(), total = 0
        for audio in archive.audio {
            try EchoValidation.filename(audio.filename)
            guard names.insert(audio.filename).inserted, clipNames.contains(audio.filename),
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
            try persist(archive.snapshot)
        } catch {
            for installedURL in installed {
                if (try? safeRegularFile(installedURL, in: recordingsDirectory)) != nil {
                    try? FileManager.default.removeItem(at: installedURL)
                }
            }
            throw error
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
