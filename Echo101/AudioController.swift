import AudioToolbox
import AVFoundation
import Combine
import Speech
import UIKit

struct SpeechPart: Sendable {
    var text: String
    var rate: Float
    var ipa: String?
}

enum CaptureProblem: Equatable, Sendable {
    case microphone, speech, mandarinAssets, failed
}

struct EchoVoice: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: String
}

/// One shared speech synthesizer for the whole app, so a tapped word can start within a moment.
@MainActor
final class AudioController: NSObject, ObservableObject {
    @Published var selectedVoiceID: String {
        didSet { defaults.set(selectedVoiceID, forKey: Self.voicePreferenceKey) }
    }
    @Published private(set) var voices: [EchoVoice] = []
    @Published private(set) var phase: AudioPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published private(set) var onDeviceChinese = false
    @Published private(set) var onDeviceEnglish = false
    @Published private(set) var isAwaitingSystemPermission = false
    @Published private(set) var activeSpeechText = ""
    @Published private(set) var activeWordIndex: Int?
    @Published private(set) var recordingGeneration = 0
    @Published private(set) var temporaryRecordingURL: URL?

    var isRecording: Bool { phase == .recording }

    private static let voicePreferenceKey = "echo101.selectedVoiceID"
    private let temporaryDirectory: URL
    private let defaults: UserDefaults
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let observations = AudioNotificationObservations()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var speechCallbacks: AudioDelegateCallbacks?
    private var recordingCallbacks: AudioDelegateCallbacks?
    private var playbackCallbacks: AudioDelegateCallbacks?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var elapsedTask: Task<Void, Never>?
    private var operationID = UUID()
    private var utterances: [ObjectIdentifier: SpeechRegistration] = [:]
    private var ownedTemporaryURLs: Set<URL> = []
    private var recordingLimit: TimeInterval = 20
    private var silenceSeconds: TimeInterval = 0
    private var captureKind: CaptureKind = .grandparent
    private let owner = AudioOwner()

    init(temporaryDirectory: URL, defaults: UserDefaults = .standard) {
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
        self.defaults = defaults
        self.selectedVoiceID = defaults.string(forKey: Self.voicePreferenceKey) ?? ""
        super.init()
        owner.controller = self
        haptic.prepare()
        refreshCapabilities()
        observeLifecycle()
        prewarm()
    }

    func refreshCapabilities() {
        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        voices = installed.map {
            let quality: String
            switch $0.quality {
            case .default: quality = "Default"
            case .enhanced: quality = "Enhanced"
            case .premium: quality = "Premium"
            @unknown default: quality = "Installed"
            }
            return EchoVoice(id: $0.identifier, name: $0.name, language: $0.language, quality: quality)
        }
        if !voices.contains(where: { $0.id == selectedVoiceID }) {
            let preferred = AVSpeechSynthesisVoice(language: "en-US")?.identifier
            selectedVoiceID = voices.first(where: { $0.id == preferred })?.id ?? voices.first?.id ?? ""
        }
        onDeviceChinese = supportsOnDevice(locale: "zh-CN")
        onDeviceEnglish = supportsOnDevice(locale: "en-US")
    }

    func prewarm() {
        refreshCapabilities()
        guard let voice = englishVoice() else { return }
        let utterance = AVSpeechUtterance(string: "ok")
        utterance.voice = voice
        utterance.volume = 0
        utterance.rate = AVSpeechUtteranceMaximumSpeechRate
        synthesizer.speak(utterance)
    }

    func speakWord(_ text: String, ipa: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speakParts([SpeechPart(text: trimmed, rate: AVSpeechUtteranceDefaultSpeechRate, ipa: ipa)])
    }

    func speakSentence(_ text: String, slowThenNormal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if slowThenNormal {
            speakParts([
                SpeechPart(text: trimmed, rate: 0.38, ipa: nil),
                SpeechPart(text: trimmed, rate: AVSpeechUtteranceDefaultSpeechRate, ipa: nil)
            ])
        } else {
            speakParts([SpeechPart(text: trimmed, rate: AVSpeechUtteranceDefaultSpeechRate, ipa: nil)])
        }
    }

    func speakParts(_ parts: [SpeechPart]) {
        interruptPlaybackOnly()
        errorMessage = nil
        activeSpeechText = ""
        activeWordIndex = nil
        let chunks = parts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !chunks.isEmpty else { return }
        refreshCapabilities()
        guard let voice = englishVoice() else {
            errorMessage = "请让爸妈看看手机"
            return
        }
        do {
            try activatePlayback()
            let token = operationID
            speechCallbacks = makeCallbacks(token: token)
            synthesizer.delegate = speechCallbacks
            phase = .speaking
            for part in chunks {
                let utterance = makeUtterance(part, voice: voice)
                utterances[ObjectIdentifier(utterance)] = SpeechRegistration(text: part.text, token: token)
                synthesizer.speak(utterance)
            }
        } catch {
            phase = .idle
            deactivateSession()
            errorMessage = "请让爸妈看看手机"
        }
    }

    func speakMandarin(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        interruptPlaybackOnly()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        do {
            try activatePlayback()
            let token = operationID
            speechCallbacks = makeCallbacks(token: token)
            synthesizer.delegate = speechCallbacks
            phase = .speaking
            utterances[ObjectIdentifier(utterance)] = SpeechRegistration(text: trimmed, token: token)
            synthesizer.speak(utterance)
        } catch {
            phase = .idle
            deactivateSession()
        }
    }

    func startGrandparentRecording() async -> CaptureProblem? {
        captureKind = .grandparent
        recordingLimit = 20
        return await startCapture(needsSpeech: true)
    }

    func startChildRecording() async -> CaptureProblem? {
        captureKind = .child
        recordingLimit = 10
        return await startCapture(needsSpeech: false)
    }

    func stopRecording() {
        guard phase == .recording else { return }
        cue(starting: false)
        finishRecording()
    }

    func playRecording(url: URL) {
        interruptPlaybackOnly()
        errorMessage = nil
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "这段录音不在了"
            return
        }
        do {
            try activatePlayback()
            let nextPlayer = try AVAudioPlayer(contentsOf: url)
            playbackCallbacks = makeCallbacks(token: operationID)
            nextPlayer.delegate = playbackCallbacks
            guard nextPlayer.prepareToPlay(), nextPlayer.play() else { throw AudioSetupError.playback }
            player = nextPlayer
            elapsed = 0
            phase = .playingRecord
            trackElapsed(token: operationID)
        } catch {
            player = nil
            playbackCallbacks = nil
            phase = .idle
            deactivateSession()
            errorMessage = "这段录音放不了"
        }
    }

    func discardTemporaryRecording() {
        if phase == .recording || phase == .speaking || phase == .playingRecord { interrupt() }
        if let url = temporaryRecordingURL { _ = removeOwnedTemporaryFile(url) }
        temporaryRecordingURL = nil
        elapsed = 0
    }

    func transcribeCurrentMandarin() async -> String? {
        guard let url = temporaryRecordingURL else { return nil }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.supportsOnDeviceRecognition,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        return await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                let finished = result?.isFinal == true || error != nil
                guard finished else { return }
                box.resume(result?.bestTranscription.formattedString)
            }
            recognitionTask = task
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(25))
                if task.state == .running {
                    task.cancel()
                    box.resume(nil)
                }
            }
        }
    }

    func interrupt() {
        operationID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        if let recorder, recorder.isRecording { recorder.stop() }
        recorder = nil
        recordingCallbacks = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
        speechCallbacks = nil
        utterances.removeAll()
        player?.stop()
        player = nil
        playbackCallbacks = nil
        phase = .idle
        activeSpeechText = ""
        activeWordIndex = nil
        silenceSeconds = 0
        deactivateSession()
    }

    private func interruptPlaybackOnly() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
        speechCallbacks = nil
        utterances.removeAll()
        player?.stop()
        player = nil
        playbackCallbacks = nil
        if phase == .speaking || phase == .playingRecord {
            phase = .idle
            deactivateSession()
        }
        activeSpeechText = ""
        activeWordIndex = nil
        operationID = UUID()
    }

    private func startCapture(needsSpeech: Bool) async -> CaptureProblem? {
        discardTemporaryRecording()
        errorMessage = nil
        isAwaitingSystemPermission = true
        let allowed = await AVAudioApplication.requestRecordPermission()
        if needsSpeech {
            _ = await speechAuthorization()
        }
        guard allowed else {
            isAwaitingSystemPermission = false
            return .microphone
        }
        if needsSpeech {
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                isAwaitingSystemPermission = false
                return .speech
            }
            guard supportsOnDevice(locale: "zh-CN") else {
                isAwaitingSystemPermission = false
                return .mandarinAssets
            }
        }
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            let url = temporaryDirectory.appendingPathComponent("echo-\(UUID().uuidString).m4a")
            guard FileManager.default.createFile(atPath: url.path, contents: Data(),
                attributes: [.protectionKey: FileProtectionType.complete]) else { throw AudioSetupError.fileCreation }
            ownedTemporaryURLs.insert(url)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let nextRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            nextRecorder.isMeteringEnabled = true
            recordingCallbacks = makeCallbacks(token: operationID)
            nextRecorder.delegate = recordingCallbacks
            guard nextRecorder.prepareToRecord(), nextRecorder.record(forDuration: recordingLimit) else { throw AudioSetupError.recording }
            recorder = nextRecorder
            temporaryRecordingURL = url
            elapsed = 0
            silenceSeconds = 0
            phase = .recording
            cue(starting: true)
            trackElapsed(token: operationID)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self.isAwaitingSystemPermission = false
            }
            return nil
        } catch {
            isAwaitingSystemPermission = false
            discardTemporaryRecording()
            return .failed
        }
    }

    private func finishRecording() {
        guard let current = recorder else {
            phase = .idle
            return
        }
        recorder = nil
        if current.isRecording { current.stop() }
        recordingCallbacks = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        silenceSeconds = 0
        phase = .idle
        deactivateSession()
        recordingGeneration += 1
    }

    private func trackElapsed(token: UUID) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.operationID == token, self.phase == .recording, let recorder = self.recorder else { return }
                self.elapsed = min(self.recordingLimit, recorder.currentTime)
                if self.captureKind == .grandparent {
                    recorder.updateMeters()
                    let power = recorder.averagePower(forChannel: 0)
                    if self.elapsed > 0.6 && power < -42 {
                        self.silenceSeconds += 0.2
                    } else {
                        self.silenceSeconds = 0
                    }
                    if self.silenceSeconds >= 3 || self.elapsed >= self.recordingLimit {
                        self.cue(starting: false)
                        self.finishRecording()
                        return
                    }
                } else if self.elapsed >= self.recordingLimit {
                    self.cue(starting: false)
                    self.finishRecording()
                    return
                }
            }
        }
    }

    private func cue(starting: Bool) {
        haptic.impactOccurred()
        haptic.prepare()
        AudioServicesPlaySystemSound(starting ? 1113 : 1114)
    }

    private func englishVoice() -> AVSpeechSynthesisVoice? {
        guard let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID), voice.language.hasPrefix("en") else {
            return AVSpeechSynthesisVoice(language: "en-US")
        }
        return voice
    }

    private func makeUtterance(_ part: SpeechPart, voice: AVSpeechSynthesisVoice) -> AVSpeechUtterance {
        let utterance: AVSpeechUtterance
        if let ipa = part.ipa?.trimmingCharacters(in: .whitespacesAndNewlines), !ipa.isEmpty {
            let attributed = NSMutableAttributedString(string: part.text)
            let range = NSRange(location: 0, length: (part.text as NSString).length)
            attributed.addAttribute(NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute), value: ipa, range: range)
            utterance = AVSpeechUtterance(attributedString: attributed)
        } else {
            utterance = AVSpeechUtterance(string: part.text)
        }
        utterance.voice = voice
        utterance.rate = part.rate
        return utterance
    }

    private func supportsOnDevice(locale: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition ?? false
    }

    private func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            let box = AuthorizationBox(continuation)
            SFSpeechRecognizer.requestAuthorization { status in box.resume(status) }
        }
    }

    private func activatePlayback() throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }

    private func deactivateSession() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    @discardableResult
    private func removeOwnedTemporaryFile(_ url: URL) -> Bool {
        guard ownedTemporaryURLs.contains(url),
              url.deletingLastPathComponent().standardizedFileURL == temporaryDirectory else { return false }
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            ownedTemporaryURLs.remove(url)
            return true
        } catch { return false }
    }

    private func observeLifecycle() {
        let owner = self.owner
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIScene.willDeactivateNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observations.tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    guard let self = owner.controller, !self.isAwaitingSystemPermission else { return }
                    if self.phase != .idle { self.interrupt() }
                }
            })
        }
        observations.tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main) { notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in
                    guard let self = owner.controller, !self.isAwaitingSystemPermission else { return }
                    self.interrupt()
                }
            })
    }

    private func speechFinished(id: ObjectIdentifier) {
        guard let item = utterances.removeValue(forKey: id), item.token == operationID else { return }
        if utterances.isEmpty {
            phase = .idle
            activeSpeechText = ""
            activeWordIndex = nil
            speechCallbacks = nil
            synthesizer.delegate = nil
            deactivateSession()
        }
    }

    private func willSpeak(id: ObjectIdentifier, range: NSRange) {
        guard let item = utterances[id], item.token == operationID else { return }
        activeSpeechText = item.text
        activeWordIndex = Self.wordIndex(in: item.text, range: range)
    }

    static func wordTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func wordIndex(in text: String, range: NSRange) -> Int {
        let ns = text as NSString
        var location = 0
        for (index, token) in wordTokens(text).enumerated() {
            let found = ns.range(of: token, options: [], range: NSRange(location: location, length: max(0, ns.length - location)))
            if found.location == NSNotFound { continue }
            let end = found.location + found.length
            if range.location < end && range.location + max(range.length, 1) > found.location { return index }
            location = end
        }
        return 0
    }

    private func recordingFinished(id: ObjectIdentifier, successfully: Bool) {
        guard let recorder, ObjectIdentifier(recorder) == id, phase == .recording else { return }
        if successfully { elapsed = recordingLimit }
        cue(starting: false)
        finishRecording()
    }

    private func playbackFinished(id: ObjectIdentifier, successfully: Bool) {
        guard let player, ObjectIdentifier(player) == id, phase == .playingRecord else { return }
        interruptPlaybackOnly()
        if !successfully { errorMessage = "这段录音放不了" }
    }

    private func makeCallbacks(token: UUID) -> AudioDelegateCallbacks {
        let owner = self.owner
        return AudioDelegateCallbacks { event in
            Task { @MainActor in
                guard let self = owner.controller, self.operationID == token else { return }
                switch event {
                case .speechFinished(let id): self.speechFinished(id: id)
                case .willSpeak(let id, let location, let length):
                    self.willSpeak(id: id, range: NSRange(location: location, length: length))
                case .recordingFinished(let id, let succeeded): self.recordingFinished(id: id, successfully: succeeded)
                case .playbackFinished(let id, let succeeded): self.playbackFinished(id: id, successfully: succeeded)
                }
            }
        }
    }
}

enum AudioPhase: Sendable { case idle, speaking, recording, playingRecord }

private enum CaptureKind { case grandparent, child }

private struct SpeechRegistration: Sendable {
    var text: String
    var token: UUID
}

private enum AudioDelegateEvent: Sendable {
    case speechFinished(ObjectIdentifier)
    case willSpeak(ObjectIdentifier, Int, Int)
    case recordingFinished(ObjectIdentifier, Bool)
    case playbackFinished(ObjectIdentifier, Bool)
}

private final class AudioDelegateCallbacks: NSObject, AVSpeechSynthesizerDelegate, AVAudioRecorderDelegate, AVAudioPlayerDelegate, Sendable {
    private let handle: @Sendable (AudioDelegateEvent) -> Void
    init(handle: @escaping @Sendable (AudioDelegateEvent) -> Void) {
        self.handle = handle
        super.init()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        handle(.speechFinished(ObjectIdentifier(utterance)))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        handle(.speechFinished(ObjectIdentifier(utterance)))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        handle(.willSpeak(ObjectIdentifier(utterance), characterRange.location, characterRange.length))
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        handle(.recordingFinished(ObjectIdentifier(recorder), flag))
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        handle(.playbackFinished(ObjectIdentifier(player), flag))
    }
}

private enum AudioSetupError: Error { case fileCreation, recording, playback }

private final class AudioOwner: @unchecked Sendable {
    weak var controller: AudioController?
}

private final class AuthorizationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>?
    init(_ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) { self.continuation = continuation }
    func resume(_ value: SFSpeechRecognizerAuthorizationStatus) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: value)
    }
}

private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }
    func resume(_ value: String?) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: value)
    }
}

private final class AudioNotificationObservations: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
