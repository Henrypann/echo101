import AudioToolbox
import AVFoundation
import Combine
import Speech
import UIKit

enum SpeechMode: Sendable { case normal, slow, parts }
enum RecordingMode: Sendable { case context, practice, grandparent, child }
enum AudioPhase: Sendable { case idle, speaking, recording, playingRecord, transcribing }

enum ListenFailure: String, Sendable {
    case permission
    case speechPermission
    case assets
    case unavailable
    case noAudio
    case notRecognized
    case interrupted
}

struct ListenResult: Sendable {
    var transcript: String
    var duration: TimeInterval
    var audioURL: URL?
    var failure: ListenFailure?
}

struct EchoVoice: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: String
}

/// Owns only unsaved recordings it creates inside the supplied temporary directory.
@MainActor
final class AudioController: NSObject, ObservableObject {
    @Published var selectedVoiceID: String {
        didSet { defaults.set(selectedVoiceID, forKey: Self.voicePreferenceKey) }
    }
    @Published private(set) var voices: [EchoVoice] = []
    @Published private(set) var phase: AudioPhase = .idle
    @Published private(set) var isSpeechPaused = false
    @Published private(set) var transcript = ""
    @Published private(set) var temporaryRecordingURL: URL?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published private(set) var onDeviceChinese = false
    @Published private(set) var onDeviceEnglish = false
    /// True while the system permission dialog is up, so inactivity does not cancel the turn.
    @Published private(set) var awaitingSystemPermission = false

    var isRecording: Bool { phase == .recording }
    var activeRecordingMode: RecordingMode { recordingMode }

    private static let voicePreferenceKey = "echo101.selectedVoiceID"
    private let temporaryDirectory: URL
    private let defaults: UserDefaults
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private let observations = AudioNotificationObservations()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var speechCallbacks: AudioDelegateCallbacks?
    private var recordingCallbacks: AudioDelegateCallbacks?
    private var playbackCallbacks: AudioDelegateCallbacks?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeRecognizer: SFSpeechRecognizer?
    private var recognitionTimeout: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var operationID = UUID()
    private var utterances: [ObjectIdentifier: UUID] = [:]
    private var ownedTemporaryURLs: Set<URL> = []
    private var recordingMode: RecordingMode = .practice
    private var recordingLocale = "zh-CN"
    private var recordingLimit: TimeInterval = 30
    private var contextCanTranscribe = false
    private var silenceStarted: Date?
    private var listenHandler: ((ListenResult) -> Void)?
    private var speechIdleHandler: (() -> Void)?
    private var childRecordingHandler: ((URL?) -> Void)?
    private let silenceLimit: TimeInterval = 3
    private let silenceThreshold: Float = -42

    init(temporaryDirectory: URL, defaults: UserDefaults = .standard) {
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
        self.defaults = defaults
        self.selectedVoiceID = defaults.string(forKey: Self.voicePreferenceKey) ?? ""
        super.init()
        refreshCapabilities()
        observeLifecycle()
    }

    func refreshCapabilities() {
        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
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

    func speak(text: String, segments: [String] = [], mode: SpeechMode = .normal) {
        interrupt()
        errorMessage = nil
        let content = mode == .parts && !segments.isEmpty ? segments : [text]
        let chunks = content.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !chunks.isEmpty else { return }
        refreshCapabilities()
        guard let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID),
              voice.language == "en-US", voices.contains(where: { $0.id == voice.identifier }) else {
            errorMessage = "No installed US English voice is available. Add a voice in iPhone Settings and try again."
            return
        }
        do {
            try activatePlayback()
            speechCallbacks = makeCallbacks(token: operationID)
            synthesizer.delegate = speechCallbacks
            phase = .speaking
            for (index, chunk) in chunks.enumerated() {
                let utterance = AVSpeechUtterance(string: chunk)
                utterance.voice = voice
                utterance.rate = mode == .slow ? 0.4 : AVSpeechUtteranceDefaultSpeechRate
                utterance.pitchMultiplier = 1.0
                utterance.postUtteranceDelay = mode == .parts && index < chunks.count - 1 ? 0.45 : 0
                utterances[ObjectIdentifier(utterance)] = operationID
                synthesizer.speak(utterance)
            }
        } catch {
            phase = .idle
            deactivateSession()
            errorMessage = "Speech playback could not start. Please try again."
        }
    }

    func startRecording(mode: RecordingMode, localeIdentifier: String = "zh-CN", permissionsAlreadyGranted: Bool = false) async {
        guard temporaryRecordingURL == nil else {
            errorMessage = "Save or discard the current recording before starting another."
            return
        }
        if phase != .idle { interrupt() }
        errorMessage = nil
        if permissionsAlreadyGranted {
            await capture(mode: mode, localeIdentifier: localeIdentifier, canTranscribe: mode == .grandparent || mode == .context)
            return
        }
        let token = operationID
        awaitingSystemPermission = true
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard operationID == token else {
            awaitingSystemPermission = false
            if phase == .idle { errorMessage = "Permission check finished. Tap Record again when you are ready." }
            return
        }
        guard allowed else {
            awaitingSystemPermission = false
            errorMessage = "Microphone access is off. Enable it in Settings to record. You can still enter a note manually."
            return
        }
        var canTranscribe = false
        if mode == .context {
            if supportsOnDevice(locale: localeIdentifier) {
                let authorization = await speechAuthorization()
                guard operationID == token else {
                    awaitingSystemPermission = false
                    if phase == .idle { errorMessage = "Permission check finished. Tap Record again when you are ready." }
                    return
                }
                canTranscribe = authorization == .authorized
                if !canTranscribe {
                    errorMessage = "On-device transcription is not authorized. Your audio will be kept; enter a note manually."
                }
            } else {
                errorMessage = "On-device transcription is unavailable for this language. Your audio will be kept; enter a note manually."
            }
        }
        awaitingSystemPermission = false
        guard operationID == token, temporaryRecordingURL == nil else { return }
        guard UIApplication.shared.applicationState == .active else {
            errorMessage = "Return to the app and tap Record again."
            return
        }
        await capture(mode: mode, localeIdentifier: localeIdentifier, canTranscribe: canTranscribe)
    }

    private func capture(mode: RecordingMode, localeIdentifier: String, canTranscribe: Bool) async {
        let token = operationID
        var createdURL: URL?
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporaryDirectory.path)
            let url = temporaryDirectory.appendingPathComponent("echo-\(UUID().uuidString).m4a")
            guard FileManager.default.createFile(atPath: url.path, contents: Data(),
                attributes: [.protectionKey: FileProtectionType.complete]) else {
                throw AudioSetupError.fileCreation
            }
            createdURL = url
            ownedTemporaryURLs.insert(url)
            try protectTemporaryFile(url)
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            let nextRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            recordingCallbacks = makeCallbacks(token: token)
            nextRecorder.delegate = recordingCallbacks
            guard nextRecorder.prepareToRecord() else { throw AudioSetupError.recording }
            try protectTemporaryFile(url)
            switch mode {
            case .context: recordingLimit = 45
            case .grandparent: recordingLimit = 20
            case .child: recordingLimit = 10
            case .practice: recordingLimit = 30
            }
            nextRecorder.isMeteringEnabled = mode == .grandparent
            guard nextRecorder.record(forDuration: recordingLimit) else { throw AudioSetupError.recording }
            recorder = nextRecorder
            recordingMode = mode
            recordingLocale = localeIdentifier
            contextCanTranscribe = canTranscribe
            transcript = ""
            elapsed = 0
            silenceStarted = nil
            temporaryRecordingURL = url
            phase = .recording
            trackElapsed(token: token)
        } catch {
            recorder?.stop()
            recorder = nil
            recordingCallbacks = nil
            let removed = createdURL.map { removeOwnedTemporaryFile($0) } ?? true
            if !removed { temporaryRecordingURL = createdURL }
            deactivateSession()
            phase = .idle
            errorMessage = removed
                ? "Recording could not start. Check available storage and try again."
                : "Recording could not start. Discard the temporary audio before trying again."
        }
    }

    func pauseSpeech() {
        guard phase == .speaking, !isSpeechPaused else { return }
        if synthesizer.pauseSpeaking(at: .immediate) { isSpeechPaused = true }
    }

    func resumeSpeech() {
        guard phase == .speaking, isSpeechPaused else { return }
        if synthesizer.continueSpeaking() { isSpeechPaused = false }
    }

    func stopRecording() {
        finishRecording(transcribe: recordingMode == .context || recordingMode == .grandparent)
    }

    /// Tap to start a Mandarin turn. Permission dialogs do not count as leaving the app.
    func beginGrandparentTurn(handler: @escaping (ListenResult) -> Void) async {
        listenHandler = handler
        guard temporaryRecordingURL == nil else {
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .interrupted))
            return
        }
        interruptPlaybackOnly()
        errorMessage = nil
        let token = operationID
        awaitingSystemPermission = true
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard operationID == token else {
            awaitingSystemPermission = false
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .interrupted))
            return
        }
        guard allowed else {
            awaitingSystemPermission = false
            errorMessage = "请让爸妈看看手机"
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .permission))
            return
        }
        guard supportsOnDevice(locale: "zh-CN") else {
            awaitingSystemPermission = false
            errorMessage = "请让爸妈看看手机"
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .assets))
            return
        }
        let authorization = await speechAuthorization()
        guard operationID == token else {
            awaitingSystemPermission = false
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .interrupted))
            return
        }
        guard authorization == .authorized else {
            awaitingSystemPermission = false
            errorMessage = "请让爸妈看看手机"
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .speechPermission))
            return
        }
        if UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(400))
        }
        awaitingSystemPermission = false
        guard operationID == token, UIApplication.shared.applicationState == .active else {
            deliverListen(ListenResult(transcript: "", duration: 0, audioURL: nil, failure: .interrupted))
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AudioServicesPlaySystemSound(1104)
        await startRecording(mode: .grandparent, localeIdentifier: "zh-CN", permissionsAlreadyGranted: true)
        if phase != .recording {
            let failure: ListenFailure = errorMessage == nil ? .unavailable : .unavailable
            deliverListen(ListenResult(transcript: "", duration: elapsed, audioURL: temporaryRecordingURL, failure: failure))
        }
    }

    func endGrandparentTurn() {
        guard recordingMode == .grandparent, phase == .recording else { return }
        stopRecording()
    }

    /// Replays one English sentence, then records the child for up to 10 seconds. No score.
    func recordChildAfterEnglish(_ english: String) async -> URL? {
        await speakEnglishAndWait(english)
        guard phase != .recording else { return nil }
        return await withCheckedContinuation { continuation in
            childRecordingHandler = { url in continuation.resume(returning: url) }
            Task { @MainActor in
                await self.startRecording(mode: .child, localeIdentifier: "en-US")
                if self.phase != .recording {
                    self.finishChildRecording(url: nil)
                }
            }
        }
    }

    func speakEnglishLesson(_ text: String) {
        speakSequence(text, language: "en-US", rates: [0.38, AVSpeechUtteranceDefaultSpeechRate])
    }

    func speakMandarin(_ text: String) {
        speakSequence(text, language: "zh-CN", rates: [AVSpeechUtteranceDefaultSpeechRate])
    }

    func speakEnglishAndWait(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            speechIdleHandler = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            speakSequence(text, language: "en-US", rates: [AVSpeechUtteranceDefaultSpeechRate])
            if phase != .speaking {
                speechIdleHandler?()
                speechIdleHandler = nil
            }
        }
    }

    func relinquishTemporaryRecording() {
        if let url = temporaryRecordingURL { ownedTemporaryURLs.remove(url) }
        temporaryRecordingURL = nil
        transcript = ""
        elapsed = 0
    }

    func playRecording(url: URL) {
        interrupt()
        errorMessage = nil
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "This recording is no longer available."
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
            errorMessage = "This recording could not be played. Please try again."
        }
    }

    func stopPlayback() {
        guard phase == .speaking || phase == .playingRecord else { return }
        interrupt()
    }

    func discardTemporaryRecording() {
        interrupt()
        if let url = temporaryRecordingURL {
            guard removeOwnedTemporaryFile(url) else {
                errorMessage = "The temporary recording could not be removed. Please try again."
                return
            }
        }
        temporaryRecordingURL = nil
        transcript = ""
        elapsed = 0
    }

    /// Lifecycle interruptions preserve the unsaved audio and never start transcription.
    func interrupt() {
        let handler = listenHandler
        let childHandler = childRecordingHandler
        let wasGrandparent = recordingMode == .grandparent && (phase == .recording || phase == .transcribing)
        let wasChild = recordingMode == .child && phase == .recording
        listenHandler = nil
        childRecordingHandler = nil
        isSpeechPaused = false
        operationID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        activeRecognizer = nil
        recognitionTimeout?.cancel()
        recognitionTimeout = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        if let recorder {
            if recorder.isRecording { elapsed = min(recordingLimit, recorder.currentTime) }
            recorder.stop()
        }
        recorder = nil
        recordingCallbacks = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
        speechCallbacks = nil
        utterances.removeAll()
        if let player { elapsed = player.currentTime; player.stop() }
        player = nil
        playbackCallbacks = nil
        phase = .idle
        deactivateSession()
        if wasGrandparent {
            if let url = temporaryRecordingURL { _ = removeOwnedTemporaryFile(url) }
            temporaryRecordingURL = nil
            transcript = ""
            handler?(ListenResult(transcript: "", duration: elapsed, audioURL: nil, failure: .interrupted))
        }
        if wasChild {
            if let url = temporaryRecordingURL { _ = removeOwnedTemporaryFile(url) }
            temporaryRecordingURL = nil
            childHandler?(nil)
        }
        speechIdleHandler?()
        speechIdleHandler = nil
    }

    private func interruptPlaybackOnly() {
        guard phase == .speaking || phase == .playingRecord else { return }
        isSpeechPaused = false
        operationID = UUID()
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
        speechCallbacks = nil
        utterances.removeAll()
        player?.stop()
        player = nil
        playbackCallbacks = nil
        phase = .idle
        deactivateSession()
        speechIdleHandler?()
        speechIdleHandler = nil
    }

    private func deliverListen(_ result: ListenResult) {
        let handler = listenHandler
        listenHandler = nil
        handler?(result)
    }

    private func finishChildRecording(url: URL?) {
        let handler = childRecordingHandler
        childRecordingHandler = nil
        handler?(url)
    }

    private func speakSequence(_ text: String, language: String, rates: [Float]) {
        if phase == .recording { return }
        interruptPlaybackOnly()
        errorMessage = nil
        let chunks = rates.map { _ in text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !chunks.isEmpty else {
            speechIdleHandler?()
            speechIdleHandler = nil
            return
        }
        let voice: AVSpeechSynthesisVoice?
        if language == "en-US" {
            refreshCapabilities()
            voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID).flatMap { candidate in
                candidate.language == "en-US" && voices.contains(where: { $0.id == candidate.identifier }) ? candidate : nil
            }
            if voice == nil {
                errorMessage = "No installed US English voice is available. Add a voice in iPhone Settings and try again."
                speechIdleHandler?()
                speechIdleHandler = nil
                return
            }
        } else {
            voice = AVSpeechSynthesisVoice(language: language)
            if voice == nil {
                errorMessage = "没有可用的中文语音。"
                speechIdleHandler?()
                speechIdleHandler = nil
                return
            }
        }
        do {
            try activatePlayback()
            speechCallbacks = makeCallbacks(token: operationID)
            synthesizer.delegate = speechCallbacks
            phase = .speaking
            for (index, rate) in rates.enumerated() {
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = rate
                utterance.pitchMultiplier = 1.0
                utterance.postUtteranceDelay = index == 0 && rates.count > 1 ? 0.35 : 0
                utterances[ObjectIdentifier(utterance)] = operationID
                synthesizer.speak(utterance)
            }
        } catch {
            phase = .idle
            deactivateSession()
            errorMessage = "Speech playback could not start. Please try again."
            speechIdleHandler?()
            speechIdleHandler = nil
        }
    }

    private func finishRecording(transcribe: Bool) {
        guard phase == .recording, let currentRecorder = recorder else { return }
        if currentRecorder.isRecording { elapsed = min(recordingLimit, currentRecorder.currentTime) }
        // Clear ownership before stop(), whose delegate callback can arrive later.
        recorder = nil
        currentRecorder.stop()
        recordingCallbacks = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        let mode = recordingMode
        let url = temporaryRecordingURL
        let heard = elapsed
        phase = .idle
        silenceStarted = nil
        deactivateSession()
        if mode == .child {
            finishChildRecording(url: url)
            return
        }
        if transcribe, (mode == .context || mode == .grandparent), contextCanTranscribe, let url {
            transcribeContext(url: url, token: operationID)
            return
        }
        if mode == .grandparent {
            deliverListen(ListenResult(transcript: "", duration: heard, audioURL: url, failure: heard < 0.4 ? .noAudio : .notRecognized))
        }
    }

    private func transcribeContext(url: URL, token: UUID) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: recordingLocale)),
              recognizer.supportsOnDeviceRecognition,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            errorMessage = "On-device transcription is unavailable. Your audio is kept; enter a note manually."
            if recordingMode == .grandparent {
                deliverListen(ListenResult(transcript: "", duration: elapsed, audioURL: url, failure: .unavailable))
            }
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        activeRecognizer = recognizer
        phase = .transcribing
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.operationID == token, self.phase == .transcribing,
                      self.temporaryRecordingURL == url else { return }
                if isFinal, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.transcript = text
                    self.finishTranscription()
                } else if failed || isFinal {
                    self.finishTranscription()
                    if self.recordingMode != .grandparent {
                        self.errorMessage = "On-device transcription could not finish. Your audio is kept; enter a note manually."
                    }
                }
            }
        }
        recognitionTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, self.operationID == token, self.phase == .transcribing else { return }
            self.finishTranscription()
            if self.recordingMode != .grandparent {
                self.errorMessage = "On-device transcription timed out. Your audio is kept; enter a note manually."
            }
        }
    }

    private func finishTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        activeRecognizer = nil
        recognitionTimeout?.cancel()
        recognitionTimeout = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = temporaryRecordingURL
        let heard = elapsed
        let mode = recordingMode
        phase = .idle
        guard mode == .grandparent else { return }
        if text.isEmpty || heard < 0.35 {
            deliverListen(ListenResult(transcript: text, duration: heard, audioURL: url, failure: text.isEmpty ? .notRecognized : .noAudio))
        } else {
            deliverListen(ListenResult(transcript: text, duration: heard, audioURL: url, failure: nil))
        }
    }

    private func trackElapsed(token: UUID) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.operationID == token else { return }
                if self.phase == .recording, let recorder = self.recorder {
                    self.elapsed = min(self.recordingLimit, recorder.currentTime)
                    if self.recordingMode == .grandparent {
                        recorder.updateMeters()
                        let power = recorder.averagePower(forChannel: 0)
                        if power < self.silenceThreshold {
                            if self.silenceStarted == nil { self.silenceStarted = Date() }
                            if let started = self.silenceStarted, Date().timeIntervalSince(started) >= self.silenceLimit {
                                self.stopRecording()
                                return
                            }
                        } else {
                            self.silenceStarted = nil
                        }
                    }
                    if self.elapsed >= self.recordingLimit { self.stopRecording(); return }
                } else if self.phase == .playingRecord, let player = self.player {
                    self.elapsed = player.currentTime
                } else { return }
            }
        }
    }

    private func supportsOnDevice(locale: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition ?? false
    }

    private func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    private func activatePlayback() throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }

    private func deactivateSession() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func protectTemporaryFile(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var securedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try securedURL.setResourceValues(values)
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
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIScene.willDeactivateNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observations.tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let inactiveOnly = note.name == UIApplication.willResignActiveNotification || note.name == UIScene.willDeactivateNotification
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if inactiveOnly && self.awaitingSystemPermission { return }
                    guard self.phase != .idle else { return }
                    self.interrupt()
                }
            })
        }
        observations.tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main) { [weak self] notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor [weak self] in self?.interrupt() }
            })
        observations.tokens.append(NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshCapabilities() }
            })
    }

    private func speechFinished(id: ObjectIdentifier) {
        guard let token = utterances.removeValue(forKey: id), token == operationID, phase == .speaking else { return }
        if utterances.isEmpty {
            phase = .idle
            isSpeechPaused = false
            speechCallbacks = nil
            synthesizer.delegate = nil
            deactivateSession()
            speechIdleHandler?()
            speechIdleHandler = nil
        }
    }

    private func recordingFinished(id: ObjectIdentifier, successfully: Bool) {
        guard let recorder, ObjectIdentifier(recorder) == id, phase == .recording else { return }
        if successfully { elapsed = recordingLimit }
        finishRecording(transcribe: successfully)
        if !successfully { errorMessage = "Recording was interrupted. Review the saved temporary audio or enter a note manually." }
    }

    private func playbackFinished(id: ObjectIdentifier, successfully: Bool) {
        guard let player, ObjectIdentifier(player) == id, phase == .playingRecord else { return }
        let duration = player.duration
        interrupt()
        if successfully { elapsed = duration }
        if !successfully { errorMessage = "Playback was interrupted. Please try again." }
    }

    private func makeCallbacks(token: UUID) -> AudioDelegateCallbacks {
        AudioDelegateCallbacks { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.operationID == token else { return }
                switch event {
                case .speechFinished(let id): self.speechFinished(id: id)
                case .recordingFinished(let id, let succeeded): self.recordingFinished(id: id, successfully: succeeded)
                case .playbackFinished(let id, let succeeded): self.playbackFinished(id: id, successfully: succeeded)
                }
            }
        }
    }
}

private enum AudioDelegateEvent: Sendable {
    case speechFinished(ObjectIdentifier)
    case recordingFinished(ObjectIdentifier, Bool)
    case playbackFinished(ObjectIdentifier, Bool)
}

/// Immutable callback closure carries its operation token across arbitrary delegate queues.
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

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        handle(.recordingFinished(ObjectIdentifier(recorder), flag))
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        handle(.recordingFinished(ObjectIdentifier(recorder), false))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        handle(.playbackFinished(ObjectIdentifier(player), flag))
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        handle(.playbackFinished(ObjectIdentifier(player), false))
    }
}

private enum AudioSetupError: Error { case fileCreation, recording, playback }

/// Observer removal is safe from deinit without accessing main-actor controller state.
private final class AudioNotificationObservations: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
