import Foundation
import Network
import Security

struct ModelHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let url: URL
}

protocol ModelTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ModelHTTPResponse
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Refuse even same-host redirects: credentials only ever reach the fixed endpoint.
        completionHandler(nil)
    }
}

final class SessionModelTransport: ModelTransport, Sendable {
    let session: URLSession
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        // The session must allow cellular so a parent toggle can opt in per request.
        // Each request still defaults to Wi-Fi only unless that toggle is on.
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
    init(configuration: URLSessionConfiguration = SessionModelTransport.configuration()) {
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func send(_ request: URLRequest) async throws -> ModelHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let url = response.url else {
            throw ModelServiceError.malformedResponse
        }
        return ModelHTTPResponse(data: data, status: response.statusCode, url: url)
    }
}

@MainActor protocol WiFiMonitoring: AnyObject {
    var available: Bool { get }
    func start(_ update: @escaping @MainActor (Bool) -> Void)
    func setAllowsCellular(_ allowed: Bool)
}

extension WiFiMonitoring {
    func setAllowsCellular(_ allowed: Bool) {}
}

private struct PathSnapshot: Sendable {
    var satisfied = false
    var wifi = false
    var expensive = false
    var constrained = false
}

@MainActor final class WiFiMonitor: WiFiMonitoring {
    private let monitor = NWPathMonitor()
    private let cellular = CellularPermission()
    private var latest = PathSnapshot()
    private var update: (@MainActor (Bool) -> Void)?
    private(set) var available = false

    func setAllowsCellular(_ allowed: Bool) {
        cellular.set(allowed)
        publish()
    }

    func start(_ update: @escaping @MainActor (Bool) -> Void) {
        self.update = update
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = PathSnapshot(
                satisfied: path.status == .satisfied,
                wifi: path.usesInterfaceType(.wifi),
                expensive: path.isExpensive,
                constrained: path.isConstrained
            )
            Task { @MainActor [weak self] in
                self?.latest = snapshot
                self?.publish()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.henrypann.echo101.wifi"))
    }

    private func publish() {
        let path = latest
        let allowed = path.satisfied && !path.constrained && (
            (path.wifi && !path.expensive) || cellular.get()
        )
        available = allowed
        update?(allowed)
    }

    deinit { monitor.cancel() }
}

/// Read from the path-monitor queue and written from the main actor.
private final class CellularPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = false
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return allowed }
    func set(_ allowed: Bool) { lock.lock(); self.allowed = allowed; lock.unlock() }
}

@MainActor protocol ModelCredentialStore: AnyObject {
    func key(for provider: ModelProvider) throws -> String?
    func set(_ value: String, for provider: ModelProvider) throws
    func delete(for provider: ModelProvider) throws
}

@MainActor final class KeychainModelCredentialStore: ModelCredentialStore {
    let service: String
    init(service: String) { self.service = service }
    private func query(_ provider: ModelProvider) -> [String: Any] {
        var result: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false
        ]
        #if os(macOS)
        result[kSecUseDataProtectionKeychain as String] = true
        #endif
        return result
    }
    func key(for provider: ModelProvider) throws -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ModelServiceError.credentialsUnavailable
        }
        return value
    }
    func set(_ value: String, for provider: ModelProvider) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(provider) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query(provider).merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ModelServiceError.credentialsUnavailable }
        } else if status != errSecSuccess { throw ModelServiceError.credentialsUnavailable }
    }
    func delete(for provider: ModelProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ModelServiceError.credentialsUnavailable }
    }
}
