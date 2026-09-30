import Foundation
import Combine

@MainActor public final class ModelService: ObservableObject {
    @Published public var configuration: ModelConfiguration {
        didSet {
            guard oldValue != configuration else { return }
            cancel()
            if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: Self.configurationKey) }
        }
    }
    @Published public private(set) var wifiAvailable: Bool
    @Published public private(set) var isBusy = false
    @Published public private(set) var requestsToday = 0
    @Published public private(set) var lastUsage = ""
    static let configurationKey = "echo101.model.configuration"
    static let quotaKey = "echo101.model.dailyQuota"
    private let defaults: UserDefaults
    private let credentials: any ModelCredentialStore
    private let network: any WiFiMonitoring
    private let transport: any ModelTransport
    private let now: () -> Date
    private var active: (id: UUID, task: Task<ModelHTTPResponse, Error>)?
    private var cancellationRevision: UInt64 = 0

    public convenience init(defaults: UserDefaults = .standard, keychainService: String = "com.henrypann.echo101.models") {
        self.init(defaults: defaults, credentials: KeychainModelCredentialStore(service: keychainService),
                  network: WiFiMonitor(), transport: SessionModelTransport(), now: Date.init)
    }
    init(defaults: UserDefaults, credentials: any ModelCredentialStore, network: any WiFiMonitoring,
         transport: any ModelTransport, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.credentials = credentials; self.network = network; self.transport = transport; self.now = now
        configuration = defaults.data(forKey: Self.configurationKey).flatMap { try? JSONDecoder().decode(ModelConfiguration.self, from: $0) } ?? ModelConfiguration()
        wifiAvailable = network.available
        refreshQuota()
        network.start { [weak self] available in
            self?.wifiAvailable = available
            if !available { self?.cancel() }
        }
    }
    deinit { active?.task.cancel() }
    public func hasKey(for provider: ModelProvider) -> Bool {
        (try? credentials.key(for: provider)).map { !$0.isEmpty } ?? false
    }
    public func setAPIKey(_ value: String, provider: ModelProvider) throws {
        guard (1...512).contains(value.count), value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }) else {
            throw ModelServiceError.invalidKey
        }
        if configuration.provider == provider { cancel() }
        try credentials.set(value, for: provider)
    }
    public func deleteAPIKey(for provider: ModelProvider) throws {
        if configuration.provider == provider { cancel() }
        try credentials.delete(for: provider)
    }
    public func generate(sceneText: String) async throws -> [ExpressionCandidate] {
        guard !sceneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sceneText.count <= 1_000,
              !sceneText.unicodeScalars.contains(where: { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }) else {
            throw ModelServiceError.invalidInput
        }
        let revision = cancellationRevision
        let parsed = try await perform(scene: sceneText, test: false)
        guard cancellationRevision == revision, !Task.isCancelled else { throw ModelServiceError.cancelled }
        let result = try ModelCodec.candidates(parsed.content)
        lastUsage = parsed.usage
        return result
    }
    public func testConnection() async throws -> String {
        let revision = cancellationRevision
        let parsed = try await perform(scene: "", test: true)
        guard cancellationRevision == revision, !Task.isCancelled else { throw ModelServiceError.cancelled }
        try ModelCodec.connection(parsed.content)
        lastUsage = parsed.usage
        return "Connection successful."
    }
    public func cancel() {
        cancellationRevision &+= 1
        active?.task.cancel()
        active = nil
        isBusy = false
    }
    private func cancel(id: UUID) { if active?.id == id { cancel() } }
    private func perform(scene: String, test: Bool) async throws -> ModelCodec.Parsed {
        guard !isBusy else { throw ModelServiceError.busy }
        guard configuration.enabled else { throw ModelServiceError.disabled }
        guard wifiAvailable && network.available else { throw ModelServiceError.wifiRequired }
        guard !configuration.modelID.isEmpty, configuration.modelID.count <= 100,
              configuration.modelID.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) }) else {
            throw ModelServiceError.invalidInput
        }
        guard let key = try credentials.key(for: configuration.provider), !key.isEmpty else { throw ModelServiceError.missingKey }
        let snapshot = configuration
        let request = try ModelCodec.request(configuration: snapshot, key: key, scene: scene, test: test)
        guard !Task.isCancelled else { throw ModelServiceError.cancelled }
        refreshQuota()
        guard requestsToday < 20 else { throw ModelServiceError.quotaExceeded }
        requestsToday += 1
        defaults.set(["day": day(), "count": requestsToday], forKey: Self.quotaKey)
        lastUsage = ""
        isBusy = true
        let id = UUID()
        let transport = transport
        let task = Task { try await transport.send(request) }
        active = (id, task)
        defer { if active?.id == id { active = nil; isBusy = false } }
        do {
            let response = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { [weak self] in
                task.cancel()
                Task { @MainActor in self?.cancel(id: id) }
            }
            guard active?.id == id, !task.isCancelled, !Task.isCancelled, configuration == snapshot,
                  wifiAvailable && network.available else { throw ModelServiceError.cancelled }
            guard response.url == snapshot.provider.endpoint else { throw ModelServiceError.networkFailure }
            guard response.status == 200 else { throw ModelServiceError.httpStatus(response.status) }
            return try ModelCodec.parseEnvelope(response.data)
        } catch {
            if active?.id != id || task.isCancelled || Task.isCancelled { throw ModelServiceError.cancelled }
            if let error = error as? ModelServiceError { throw error }
            if let error = error as? URLError {
                if error.code == .timedOut { throw ModelServiceError.timedOut }
                if error.code == .cancelled { throw ModelServiceError.cancelled }
            }
            throw ModelServiceError.networkFailure
        }
    }
    private func day() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    private func refreshQuota() {
        let record = defaults.dictionary(forKey: Self.quotaKey)
        if record?["day"] as? String == day() {
            requestsToday = min(20, max(0, record?["count"] as? Int ?? 20))
        } else {
            requestsToday = 0
            defaults.set(["day": day(), "count": 0], forKey: Self.quotaKey)
        }
    }
}
