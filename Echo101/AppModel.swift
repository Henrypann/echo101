import Foundation
import Combine
import UIKit
import LocalAuthentication
import EchoCore
import EchoAPI

typealias Expression = EchoCore.Expression

@MainActor
final class AppModel: ObservableObject {
    let store: EchoStore?
    let audio: AudioController?
    let api: ModelService
    @Published var errorMessage: String?
    @Published private(set) var isParentMode = false
    @Published private(set) var isAuthenticatingParent = false
    @Published var parentGateError: String?
    @Published var parentTab = 0
    @Published var childTab = 0
    @Published var reminderVisible = false
    @Published var reminderMinutes: Int {
        didSet {
            preferences.set(reminderMinutes, forKey: "echo.reminderMinutes")
            startActivityReminder()
        }
    }
    private let preferences: UserDefaults
    private var parentAuthentication: LAContext?
    private var gateToken = UUID()
    private var reminderTask: Task<Void, Never>?
    let snapshotPage: String?
    let snapshotAppearance: String?
    let snapshotLargeText: Bool
    static let scenes = ["Everyday", "Toys", "Food", "Outdoors", "Songs", "Getting Ready", "Bedtime"]

    init() {
        let defaults: UserDefaults
        let keychainService: String
        let directoryName: String
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let isTest = args.contains("--uitesting")
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        snapshotPage = isTest ? value(after: "--snapshot-page") : nil
        snapshotAppearance = isTest ? value(after: "--appearance") : nil
        snapshotLargeText = isTest && args.contains("--large-text")
        let runID: UUID = args.firstIndex(of: "--test-run-id").flatMap { i in
            args.indices.contains(i + 1) ? UUID(uuidString: args[i + 1]) : nil
        } ?? UUID()
        defaults = isTest ? UserDefaults(suiteName: "echo101.tests.\(runID.uuidString)")! : .standard
        keychainService = isTest ? "echo101.tests.\(runID.uuidString)" : "com.henrypann.echo101.models"
        directoryName = isTest ? "EchoTests-\(runID.uuidString)" : "EchoData"
        #else
        snapshotPage = nil; snapshotAppearance = nil; snapshotLargeText = false
        defaults = .standard
        keychainService = "com.henrypann.echo101.models"
        directoryName = "EchoData"
        #endif
        preferences = defaults
        let savedMinutes = defaults.object(forKey: "echo.reminderMinutes") as? Int ?? 5
        reminderMinutes = [0, 3, 5, 10].contains(savedMinutes) ? savedMinutes : 5
        api = ModelService(defaults: defaults, keychainService: keychainService)
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(directoryName, isDirectory: true)
            let loaded = try EchoStore(directory: root)
            store = loaded
            let controller = AudioController(temporaryDirectory: loaded.temporaryDirectory, defaults: defaults)
            audio = controller
            #if DEBUG
            if isTest {
                api.configuration.enabled = false
                if args.contains("--seed-samples"), loaded.snapshot.isEmpty { try? seedPreviewLibrary(loaded) }
                if args.contains("--test-parent") || ["overview", "moment", "review", "settings", "moments"].contains(snapshotPage ?? "") { isParentMode = true }
                parentTab = snapshotPage == "settings" ? 2 : snapshotPage == "moments" ? 1 : 0
                childTab = snapshotPage == "explore" ? 1 : snapshotPage == "world" ? 2 : 0
                writeDiagnostics(store: loaded, audio: controller)
            }
            #endif
        } catch {
            store = nil; audio = nil
            errorMessage = "Echo could not open local storage. Existing files were not reset. Please close the app and try again."
        }
    }

    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }

    func requestParentAccess() async {
        guard !isAuthenticatingParent, !isParentMode else { return }
        parentGateError = nil
        let context = LAContext()
        var capabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &capabilityError) else {
            parentGateError = "Set a device passcode in iPhone Settings to open the parent area. Saved words are still available here."
            return
        }
        let token = UUID(); gateToken = token
        parentAuthentication = context; isAuthenticatingParent = true
        do {
            let granted = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open Echo's parent area to manage family moments and privacy settings.")
            guard gateToken == token else { return }
            isAuthenticatingParent = false; parentAuthentication = nil
            if granted { audio?.interrupt(); api.cancel(); stopActivityReminder(); parentTab = 0; isParentMode = true }
        } catch {
            guard gateToken == token else { return }
            isAuthenticatingParent = false; parentAuthentication = nil
            parentGateError = "The parent area stayed locked. Try again when an adult is ready."
        }
    }

    func leaveParentArea() {
        gateToken = UUID(); parentAuthentication?.invalidate(); parentAuthentication = nil
        isAuthenticatingParent = false; parentGateError = nil; isParentMode = false
        audio?.interrupt(); api.cancel(); stopActivityReminder()
    }

    func startActivityReminder() {
        stopActivityReminder()
        guard !isParentMode, UIApplication.shared.applicationState == .active,
              [3, 5, 10].contains(reminderMinutes), snapshotPage == nil else { return }
        let seconds = reminderMinutes * 60
        reminderTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !self.isParentMode, UIApplication.shared.applicationState == .active else { return }
            self.reminderVisible = true
        }
    }

    func stopActivityReminder() { reminderTask?.cancel(); reminderTask = nil; reminderVisible = false }
    func finishActivity() { audio?.interrupt(); stopActivityReminder(); childTab = 0 }

    /// Debug screenshots use an isolated library and never start audio or networking.
    func captureScreenshotIfRequested() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitesting"), args.contains("--snapshot"), let store else { return }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(4))
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                      let window = scene.windows.first(where: \.isKeyWindow) else { return }
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                var rendered = false
                let picture = renderer.image { _ in rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                guard rendered, let png = picture.pngData() else { return }
                try png.write(to: store.directory.appendingPathComponent("Screenshot.png"), options: [.atomic, .completeFileProtection])
            } catch { /* Diagnostic failure never changes the family library. */ }
        }
        #endif
    }

    #if DEBUG
    private func seedPreviewLibrary(_ store: EchoStore) throws {
        let toy = try store.createMoment(scene: "Toys", note: "今天一起玩红色小汽车，然后把它收进盒子。")
        let food = try store.createMoment(scene: "Food", note: "Snack time with an apple and a glass of water.")
        let car = Expression(momentID: toy.id, text: "A red car.", meaning: "一辆红色的小汽车。", segments: ["A red", "car."], isFavorite: true, source: "sample")
        let apple = Expression(momentID: food.id, text: "I want an apple.", meaning: "我想要一个苹果。", isFavorite: true, source: "sample")
        try store.saveExpressions([car, apple, Expression(momentID: toy.id, text: "Put the car in the box.", meaning: "把小汽车放进盒子。", segments: ["Put the car", "in the box."], isConfirmed: false, source: "sample draft", parentTip: "收玩具时一起说，不需要孩子完整跟读。")])
        // Synthetic records exist only in this explicit isolated diagnostic library.
        try store.recordUsage(expressionID: car.id, kind: .play)
    }

    /// Capability-only evidence in the isolated test container. No mic, model calls or family content.
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
            "voices": audio.voices.map { ["id": $0.id, "name": $0.name, "quality": $0.quality] },
            "rootExcludedFromBackup": resources?.isExcludedFromBackup ?? false,
            "rootProtection": String(describing: attributes?[.protectionKey] ?? "unknown"),
            "microphoneStarted": false
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: store.directory.appendingPathComponent("Diagnostics.json"), options: [.atomic, .completeFileProtection])
        }
    }
    #endif

    func addSamples() throws {
        guard let store else { return }
        let moment = try store.createMoment(scene: "Everyday", note: "Sample phrases for listening together. These are examples, not observations about your child.")
        let examples: [(String, String)] = [
            ("car", "汽车"), ("a red car", "一辆红色的小汽车"), ("water", "水"), ("Water, please.", "请给我水。"),
            ("I can say my ABC.", "我会说 ABC。"), ("Put it in.", "把它放进去。"), ("a big truck", "一辆大卡车"),
            ("I see a dog.", "我看见一只小狗。"), ("My turn.", "轮到我了。"), ("More, please.", "请再给我一点。"),
            ("Let's go!", "我们走吧！"), ("Open the box.", "打开盒子。"), ("Close the door.", "关上门。"),
            ("Wash your hands.", "洗洗手。"), ("Good morning.", "早上好。"), ("Good night.", "晚安。"),
            ("I want milk.", "我想喝牛奶。"), ("Here you are.", "给你。"), ("Thank you.", "谢谢。"), ("All done!", "完成啦！")
        ]
        let expressions = examples.map { text, meaning in
            Expression(momentID: moment.id, text: text, meaning: meaning,
                spokenText: text == "I can say my ABC." ? "I can say my A, B, C." : "",
                segments: text == "I can say my ABC." ? ["I can say", "my A, B, C"] : [], source: "sample")
        }
        try store.saveExpressions(expressions)
    }
}
