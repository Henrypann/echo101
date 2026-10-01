import AVFoundation
import Foundation
import Combine
import Speech
import UIKit
import LocalAuthentication
import EchoCore
import EchoAPI

@MainActor
final class AppModel: ObservableObject {
    enum Step: Equatable {
        case waiting
        case listening
        case result(UUID)
        case notice(String, NoticeKind)
    }

    enum NoticeKind: Equatable {
        case again
        case dismiss
    }

    let store: EchoStore?
    let audio: AudioController?
    let api: ModelService
    @Published var step: Step = .waiting
    @Published var isParentArea = false
    @Published var setupIssues: [String] = []
    @Published var childSaved = false
    @Published var parentStatus = ""
    @Published var keyUnlocked = false
    let snapshotLargeText: Bool
    private let preferences: UserDefaults
    private static let setupKey = "echo.setupIssues"

    init() {
        let defaults: UserDefaults
        let keychainService: String
        let directoryName: String
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        let testing = args.contains("--uitesting")
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        snapshotLargeText = testing && args.contains("--large-text")
        let runID: UUID = args.firstIndex(of: "--test-run-id").flatMap { index in
            args.indices.contains(index + 1) ? UUID(uuidString: args[index + 1]) : nil
        } ?? UUID()
        defaults = testing ? UserDefaults(suiteName: "echo101.tests.\(runID.uuidString)")! : .standard
        keychainService = testing ? "echo101.tests.\(runID.uuidString)" : "com.henrypann.echo101.models"
        directoryName = testing ? "EchoTests-\(runID.uuidString)" : "EchoData"
        #else
        snapshotLargeText = false
        defaults = .standard
        keychainService = "com.henrypann.echo101.models"
        directoryName = "EchoData"
        #endif
        preferences = defaults
        setupIssues = defaults.stringArray(forKey: Self.setupKey) ?? []
        api = ModelService(defaults: defaults, keychainService: keychainService)
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(directoryName, isDirectory: true)
            let loaded = try EchoStore(directory: root)
            store = loaded
            let controller = AudioController(temporaryDirectory: loaded.temporaryDirectory, defaults: defaults)
            audio = controller
            if loaded.snapshot.isEmpty { try? loaded.installSeedLibrary() }
            var configuration = api.configuration
            configuration.allowCellular = loaded.snapshot.settings.allowCellular
            configuration.enabled = loaded.snapshot.settings.consentGranted
            api.configuration = configuration
            #if DEBUG
            if testing {
                api.configuration.enabled = loaded.snapshot.settings.consentGranted
                if args.contains("--seed-pending"), !loaded.snapshot.records.contains(where: { $0.recognizedText == "宝宝要喝水" }) {
                    try? seedPending(loaded)
                }
                if args.contains("--test-parent") { isParentArea = true }
                writeDiagnostics(store: loaded, audio: controller)
            }
            #endif
        } catch {
            store = nil
            audio = nil
            parentStatus = "本机资料暂时打不开。原来的文件没有被覆盖，请完全退出后再打开。"
        }
    }

    var pendingCount: Int { store?.snapshot.pendingRecords.count ?? 0 }

    var exportOverdue: Bool {
        guard let date = store?.snapshot.settings.lastExportAt else { return true }
        return Date().timeIntervalSince(date) > 7 * 24 * 60 * 60
    }

    var badgeCount: Int { pendingCount + setupIssues.count + (exportOverdue ? 1 : 0) }

    var modelAllowed: Bool {
        guard let store else { return false }
        guard store.snapshot.settings.consentGranted, api.configuration.enabled, api.hasKey(for: api.configuration.provider) else { return false }
        return api.wifiAvailable
    }

    func toggleListening() {
        guard let audio else { return }
        childSaved = false
        if audio.phase == .recording, audio.activeRecordingMode == .grandparent {
            audio.endGrandparentTurn()
            return
        }
        guard step != .listening else { return }
        step = .listening
        Task { await self.startListening() }
    }

    private func startListening() async {
        guard let audio else { return }
        await audio.beginGrandparentTurn { [weak self] result in
            Task { @MainActor in self?.finishListening(result) }
        }
    }

    private func finishListening(_ result: ListenResult) {
        guard let store, let audio else { return }
        if let failure = result.failure {
            discardListenAudio(result.audioURL)
            switch failure {
            case .permission:
                rememberSetup("麦克风还没有允许")
                showNotice("请让爸妈看看手机", kind: .dismiss)
            case .speechPermission:
                rememberSetup("语音识别还没有允许")
                showNotice("请让爸妈看看手机", kind: .dismiss)
            case .assets:
                rememberSetup("还没有下载普通话（中国大陆）离线语音")
                showNotice("请让爸妈看看手机", kind: .dismiss)
            case .unavailable:
                rememberSetup("这台手机暂时不能做离线语音识别")
                showNotice("请让爸妈看看手机", kind: .dismiss)
            case .interrupted:
                step = .waiting
            case .noAudio, .notRecognized:
                showNotice("没听清，请再说一遍", kind: .again)
            }
            return
        }
        let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            discardListenAudio(result.audioURL)
            showNotice("没听清，请再说一遍", kind: .again)
            return
        }
        switch PhraseMatcher.plan(utterance: transcript, library: store.snapshot.library, modelAllowed: modelAllowed) {
        case .library(let phrase):
            let record = PhraseMatcher.matchedRecord(utterance: transcript, phrase: phrase)
            storeTurn(record, audioURL: result.audioURL, role: "grandparent")
            try? store.recordUsage(expressionID: phrase.id, kind: .play)
            step = .result(record.id)
            audio.speakEnglishLesson(record.english)
        case .askModel:
            Task { await self.askModel(transcript: transcript, audioURL: result.audioURL) }
        case .saveForParent:
            let record = PhraseMatcher.pendingRecord(utterance: transcript)
            storeTurn(record, audioURL: result.audioURL, role: "grandparent")
            showNotice("这句先记下了，爸妈晚上补英文", kind: .dismiss)
        }
    }

    private func askModel(transcript: String, audioURL: URL?) async {
        guard let store, let audio else { return }
        do {
            let scene = String(transcript.prefix(1_000))
            let candidates = try await api.generate(sceneText: scene)
            guard let first = candidates.first else { throw ModelServiceError.malformedResponse }
            let record = PhraseMatcher.generatedRecord(utterance: transcript, english: first.text, chinese: first.meaning)
            storeTurn(record, audioURL: audioURL, role: "grandparent")
            step = .result(record.id)
            audio.speakEnglishLesson(record.english)
        } catch {
            let record = PhraseMatcher.pendingRecord(utterance: transcript)
            storeTurn(record, audioURL: audioURL, role: "grandparent")
            showNotice("这句先记下了，爸妈晚上补英文", kind: .dismiss)
        }
    }

    func playEnglish(for recordID: UUID) {
        guard let store, let audio, let record = store.snapshot.records.first(where: { $0.id == recordID }), !record.english.isEmpty else { return }
        audio.speakEnglishLesson(record.english)
        if let phraseID = record.phraseID, store.snapshot.library.contains(where: { $0.id == phraseID }), !record.needsConfirmation {
            try? store.recordUsage(expressionID: phraseID, kind: .play)
        }
    }

    func replayLast() {
        guard let record = lastSpokenRecord else { return }
        playEnglish(for: record.id)
    }

    func childFollow(recordID: UUID) async {
        guard let store, let audio, let record = store.snapshot.records.first(where: { $0.id == recordID }), !record.english.isEmpty else { return }
        childSaved = false
        let url = await audio.recordChildAfterEnglish(record.english)
        guard let url else { return }
        do {
            _ = try store.addRecordRecording(recordID: recordID, role: "child", temporaryURL: url)
            childSaved = true
        } catch {
            parentStatus = "跟读录音没有保存下来。这句话的英文还在。"
            try? FileManager.default.removeItem(at: url)
        }
        audio.relinquishTemporaryRecording()
    }

    func sayAgain() {
        audio?.interrupt()
        childSaved = false
        step = .waiting
        toggleListening()
    }

    func dismissNotice() {
        audio?.interrupt()
        step = .waiting
    }

    var lastSpokenRecord: SpeechRecord? {
        store?.snapshot.records
            .filter { !$0.english.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func enterParentArea() {
        audio?.interrupt()
        api.cancel()
        childSaved = false
        step = .waiting
        isParentArea = true
    }

    func leaveParentArea() {
        audio?.interrupt()
        api.cancel()
        keyUnlocked = false
        isParentArea = false
        step = .waiting
    }

    func flushAndLeaveParent() {
        try? store?.flushUsage()
        leaveParentArea()
    }

    func authorizeKeyEntry() async -> Bool {
        let context = LAContext()
        var capability: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &capability) else {
            parentStatus = "请先在 iPhone 设置里打开设备密码，才能填写 API Key。"
            keyUnlocked = false
            return false
        }
        do {
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "填写模型 API Key。句库和录音不需要这一步。") { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
            keyUnlocked = granted
            if !granted { parentStatus = "没有通过设备密码，Key 没有打开。" }
            return granted
        } catch {
            keyUnlocked = false
            parentStatus = "没有通过设备密码，Key 没有打开。"
            return false
        }
    }

    func setConsent(_ granted: Bool) {
        guard let store else { return }
        do {
            try store.updateSettings { $0.consentGranted = granted }
            api.configuration.enabled = granted
            parentStatus = granted ? "已同意在没有合适句子时，把识别出的中文发给模型。" : "已关闭模型。匹配不到的句子会留给爸妈补英文。"
        } catch {
            parentStatus = "这个设置没有保存下来。"
        }
    }

    func setCellular(_ allowed: Bool) {
        guard let store else { return }
        do {
            try store.updateSettings { $0.allowCellular = allowed }
            api.configuration.allowCellular = allowed
            parentStatus = allowed ? "没有 Wi-Fi 时也可以用蜂窝数据问模型。" : "模型只用 Wi-Fi。"
        } catch {
            parentStatus = "这个设置没有保存下来。"
        }
    }

    func setProvider(_ provider: ModelProvider) {
        api.configuration.provider = provider
        api.configuration.modelID = provider.defaultModelID
    }

    func refreshSetupIssues() {
        guard let audio else { return }
        audio.refreshCapabilities()
        var issues = setupIssues
        if AVAudioApplication.shared.recordPermission == .granted {
            issues.removeAll { $0.contains("麦克风") }
        }
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            issues.removeAll { $0.contains("语音识别") }
        }
        if audio.onDeviceChinese {
            issues.removeAll { $0.contains("普通话") || $0.contains("离线语音识别") }
        }
        setupIssues = issues
        preferences.set(issues, forKey: Self.setupKey)
    }

    func clearAllContent() {
        guard let store else { return }
        do {
            try store.deleteAllContent()
            parentStatus = "本机内容已清空。"
        } catch {
            parentStatus = "没有清空完成。请再试一次。"
        }
    }

    private func storeTurn(_ record: SpeechRecord, audioURL: URL?, role: String) {
        guard let store, let audio else { return }
        do {
            try store.saveRecord(record)
            if let audioURL {
                _ = try store.addRecordRecording(recordID: record.id, role: role, temporaryURL: audioURL)
            }
        } catch {
            parentStatus = "这句话没有完整保存。"
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        }
        audio.relinquishTemporaryRecording()
    }

    private func discardListenAudio(_ url: URL?) {
        audio?.relinquishTemporaryRecording()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func showNotice(_ text: String, kind: NoticeKind) {
        step = .notice(text, kind)
        audio?.speakMandarin(text)
    }

    private func rememberSetup(_ issue: String) {
        guard !setupIssues.contains(issue) else { return }
        setupIssues.append(issue)
        preferences.set(setupIssues, forKey: Self.setupKey)
    }

    #if DEBUG
    private func seedPending(_ store: EchoStore) throws {
        let record = PhraseMatcher.generatedRecord(utterance: "宝宝要喝水", english: "Water, please.", chinese: "请给我水。")
        try store.saveRecord(record)
    }

    private func writeDiagnostics(store: EchoStore, audio: AudioController) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: store.directory.path)
        let resources = try? store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let report: [String: Any] = [
            "localStoreOpened": true,
            "cloudEnabled": api.configuration.enabled,
            "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "chineseOnDeviceRecognitionSupported": audio.onDeviceChinese,
            "englishOnDeviceRecognitionSupported": audio.onDeviceEnglish,
            "selectedVoiceID": audio.selectedVoiceID,
            "rootExcludedFromBackup": resources?.isExcludedFromBackup ?? false,
            "rootProtection": String(describing: attributes?[.protectionKey] ?? "unknown"),
            "microphoneStarted": false,
            "uiTest": true
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: store.directory.appendingPathComponent("Diagnostics.json"), options: [.atomic, .completeFileProtection])
        }
    }
    #endif
}
