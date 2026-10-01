import AVFoundation
import Foundation
import Combine
import LocalAuthentication
import SwiftUI
import EchoCore
import EchoAPI

enum SpeakPhase: Equatable {
    case waiting
    case listening
    case working
    case result(UUID)
    case notice(String)
}

enum FollowPhase: Equatable {
    case idle
    case replaying
    case recording
    case saved
}

@MainActor
final class AppModel: ObservableObject {
    let store: EchoStore?
    let audio: AudioController?
    let api: ModelService
    let vocabulary: VocabularyCatalog
    @Published var tab = 0
    @Published var parentUnlocked = false
    @Published var speakPhase: SpeakPhase = .waiting
    @Published var followPhase: FollowPhase = .idle
    @Published var statusLine: String?
    @Published var keyUnlocked = false
    @Published var backgroundedAt: Date?
    private var resolvingCapture = false
    private let isUITest: Bool

    init() {
        let defaults: UserDefaults
        let keychainService: String
        let directoryName: String
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        isUITest = args.contains("--uitesting")
        let runID: UUID = args.firstIndex(of: "--test-run-id").flatMap { index in
            args.indices.contains(index + 1) ? UUID(uuidString: args[index + 1]) : nil
        } ?? UUID()
        defaults = isUITest ? UserDefaults(suiteName: "echo101.tests.\(runID.uuidString)")! : .standard
        keychainService = isUITest ? "echo101.tests.\(runID.uuidString)" : "com.henrypann.echo101.models"
        directoryName = isUITest ? "EchoTests-\(runID.uuidString)" : "EchoData"
        #else
        isUITest = false
        defaults = .standard
        keychainService = "com.henrypann.echo101.models"
        directoryName = "EchoData"
        #endif
        vocabulary = (try? VocabularyCatalog.load()) ?? VocabularyCatalog(categories: [])
        api = ModelService(defaults: defaults, keychainService: keychainService)
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(directoryName, isDirectory: true)
            let loaded = try EchoStore(directory: root)
            store = loaded
            audio = AudioController(temporaryDirectory: loaded.temporaryDirectory, defaults: defaults)
            if !isUITest { try? loaded.installSeedPhrasesIfEmpty() }
            api.configuration.allowsCellular = loaded.snapshot.allowCellular
            #if DEBUG
            if isUITest { api.configuration.enabled = false }
            #endif
        } catch {
            store = nil
            audio = nil
            statusLine = "请让爸妈看看手机"
        }
    }

    var pendingCount: Int { store?.snapshot.records.filter(\.waitsForParent).count ?? 0 }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
            parentUnlocked = false
            keyUnlocked = false
            if audio?.isAwaitingSystemPermission != true {
                audio?.interrupt()
            }
            api.cancel()
            try? store?.flushUsage()
        case .inactive:
            if audio?.isAwaitingSystemPermission != true {
                audio?.interrupt()
            }
        case .active:
            if let start = backgroundedAt, Date().timeIntervalSince(start) > 10 * 60 {
                tab = 0
                speakPhase = .waiting
            }
            backgroundedAt = nil
        @unknown default:
            break
        }
    }

    func lockParentIfNeeded(from oldTab: Int, to newTab: Int) {
        if oldTab == 3 && newTab != 3 {
            parentUnlocked = false
            keyUnlocked = false
        }
    }

    func toggleRecording() async {
        guard let audio else { return }
        if speakPhase == .listening {
            audio.stopRecording()
            await resolveCapture()
            return
        }
        followPhase = .idle
        audio.discardTemporaryRecording()
        let problem = await audio.startGrandparentRecording()
        if let problem {
            await noteSetup(problem)
            return
        }
        speakPhase = .listening
    }

    func recordingDidStop() async {
        guard speakPhase == .listening, audio?.phase != .recording else { return }
        await resolveCapture()
    }

    func followDidStop() async {
        guard followPhase == .recording, audio?.phase != .recording, let audio, let store else { return }
        guard let url = audio.temporaryRecordingURL, let recordID = currentRecordID else {
            followPhase = .idle
            return
        }
        if (try? store.attachChildAudio(recordID: recordID, temporaryURL: url)) != nil {
            followPhase = .saved
            if let wordID = followWordID { try? store.markWordRepeated(wordID) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if followPhase == .saved { followPhase = .idle }
            }
        } else {
            followPhase = .idle
            showNotice("请让爸妈看看手机")
        }
    }

    private var currentRecordID: UUID? {
        if case .result(let id) = speakPhase { return id }
        return followRecordID
    }
    private var followRecordID: UUID?
    private var followWordID: String?

    func playEnglish(for record: SpokenRecord) {
        let phrase = store?.snapshot.phrases.first { $0.id == record.phraseID }
        let text = phrase?.speechText ?? record.english
        guard !text.isEmpty else { return }
        audio?.speakSentence(text, slowThenNormal: true)
    }

    func playToday(_ record: SpokenRecord) {
        playEnglish(for: record)
    }

    func playChild(filename: String) {
        guard let store, let url = try? store.audioURL(filename: filename) else { return }
        audio?.playRecording(url: url)
    }

    func sayAgain() {
        audio?.interrupt()
        followPhase = .idle
        speakPhase = .waiting
    }

    func beginFollow(record: SpokenRecord, wordID: String? = nil) async {
        let phrase = store?.snapshot.phrases.first { $0.id == record.phraseID }
        let text = phrase?.speechText ?? record.english
        guard !text.isEmpty, let audio else { return }
        followRecordID = record.id
        followWordID = wordID
        followPhase = .replaying
        audio.speakSentence(text, slowThenNormal: false)
        while audio.phase == .speaking {
            try? await Task.sleep(for: .milliseconds(120))
        }
        guard followPhase == .replaying else { return }
        let problem = await audio.startChildRecording()
        if let problem {
            followPhase = .idle
            await noteSetup(problem)
            return
        }
        followPhase = .recording
    }

    func stopFollow() {
        audio?.stopRecording()
        Task { await followDidStop() }
    }

    func playWord(_ word: VocabularyWord) {
        audio?.speakWord(word.english, ipa: word.ipa.isEmpty ? nil : word.ipa)
    }

    func playWordLesson(_ word: VocabularyWord) {
        let ipa = word.ipa.isEmpty ? nil : word.ipa
        audio?.speakParts([
            SpeechPart(text: word.english, rate: AVSpeechUtteranceDefaultSpeechRate, ipa: ipa),
            SpeechPart(text: word.exampleEn, rate: 0.38, ipa: nil),
            SpeechPart(text: word.exampleEn, rate: AVSpeechUtteranceDefaultSpeechRate, ipa: nil)
        ])
    }

    func practiceWord(_ word: VocabularyWord) async {
        guard let store else { return }
        let record = SpokenRecord(
            recognizedText: word.chinese,
            english: word.exampleEn,
            chineseMeaning: word.exampleZh,
            kind: .library)
        guard let saved = try? store.addSpokenRecord(record) else {
            showNotice("请让爸妈看看手机")
            return
        }
        speakPhase = .result(saved.id)
        await beginFollow(record: saved, wordID: word.id)
    }

    func authorizeKeyEntry() async -> Bool {
        #if DEBUG
        if isUITest { keyUnlocked = true; return true }
        #endif
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        let granted = await withCheckedContinuation { continuation in
            let box = AuthReplyBox(continuation)
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "填写模型 API Key。") { ok, _ in
                box.resume(ok)
            }
        }
        keyUnlocked = granted
        return granted
    }

    func setConsent(_ granted: Bool) {
        try? store?.setModelConsent(granted: granted)
        api.configuration.enabled = granted
    }

    func setCellular(_ allowed: Bool) {
        try? store?.setAllowCellular(allowed)
        api.configuration.allowsCellular = allowed
    }

    private func resolveCapture() async {
        guard !resolvingCapture else { return }
        resolvingCapture = true
        defer { resolvingCapture = false }
        guard let audio, let store else { return }
        speakPhase = .working
        let text = await audio.transcribeCurrentMandarin()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let consent = store.snapshot.consentGrantedAt != nil
        let modelReady = api.configuration.enabled && api.hasKey(for: api.configuration.provider) && networkReady
        switch UtterancePlanner.plan(text: trimmed, phrases: store.snapshot.phrases, consent: consent, modelReady: modelReady) {
        case .unheard:
            audio.discardTemporaryRecording()
            showNotice("没听清，请再说一遍")
        case .library(let phrase):
            await save(record: SpokenRecord(
                recognizedText: trimmed,
                english: phrase.english,
                chineseMeaning: phrase.chinese,
                phraseID: phrase.id,
                kind: .library), audio: audio)
        case .callModel:
            do {
                let candidates = try await api.generate(sceneText: String(trimmed.prefix(1_000)))
                guard let first = candidates.first else { throw ModelServiceError.malformedResponse }
                await save(record: SpokenRecord(
                    recognizedText: trimmed,
                    english: first.text,
                    chineseMeaning: first.meaning,
                    kind: .pendingParent), audio: audio)
            } catch {
                await savePending(trimmed, audio: audio)
            }
        case .savePending:
            await savePending(trimmed, audio: audio)
        }
    }

    private func savePending(_ text: String, audio: AudioController) async {
        await save(record: SpokenRecord(recognizedText: text, kind: .pendingParent), audio: audio, notice: "这句先记下了，爸妈晚上补英文")
    }

    private func save(record: SpokenRecord, audio: AudioController, notice: String? = nil) async {
        guard let store else { return }
        do {
            let saved = try store.addSpokenRecord(record, audioTemporaryURL: audio.temporaryRecordingURL)
            if let notice {
                showNotice(notice)
            } else {
                speakPhase = .result(saved.id)
            }
        } catch {
            audio.discardTemporaryRecording()
            showNotice("请让爸妈看看手机")
        }
    }

    private var networkReady: Bool {
        guard let store else { return false }
        if store.snapshot.allowCellular { return api.networkReachable || api.wifiAvailable }
        return api.wifiAvailable
    }

    private func noteSetup(_ problem: CaptureProblem) async {
        let code: String
        switch problem {
        case .microphone: code = "microphone"
        case .speech: code = "speech"
        case .mandarinAssets: code = "mandarin-assets"
        case .failed: code = "recording"
        }
        try? store?.logSetupIssue(code: code, message: "请检查麦克风、语音识别，或下载普通话（中国大陆）离线语音。")
        showNotice("请让爸妈看看手机")
    }

    private func showNotice(_ text: String) {
        speakPhase = .notice(text)
        audio?.speakMandarin(text)
    }

    func record(id: UUID) -> SpokenRecord? {
        store?.snapshot.records.first { $0.id == id }
    }
}

private final class AuthReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func resume(_ value: Bool) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: value)
    }
}
