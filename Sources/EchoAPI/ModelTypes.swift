import Foundation

public enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepSeek, miMo
    public var id: String { rawValue }
    public var title: String { self == .deepSeek ? "DeepSeek" : "MiMo" }
    public var defaultModelID: String { self == .deepSeek ? "deepseek-flash" : "mimo-v2.6-pro" }
    var endpoint: URL {
        URL(string: self == .deepSeek ? "https://api.deepseek.com/chat/completions" : "https://api.xiaomimimo.com/v1/chat/completions")!
    }
}

public struct ModelConfiguration: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var modelID: String
    public var enabled: Bool
    public init(provider: ModelProvider = .deepSeek, modelID: String? = nil, enabled: Bool = false) {
        self.provider = provider
        self.modelID = modelID ?? provider.defaultModelID
        self.enabled = enabled
    }
}

public struct ExpressionCandidate: Codable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var meaning: String
    public var segments: [String]
    public var tip: String
    public init(id: UUID = UUID(), text: String, meaning: String, segments: [String] = [], tip: String = "") {
        self.id = id; self.text = text; self.meaning = meaning; self.segments = segments; self.tip = tip
    }
}

public enum ModelServiceError: Error, Equatable, LocalizedError, Sendable {
    case disabled, missingKey, wifiRequired, busy, quotaExceeded, invalidInput, invalidKey
    case credentialsUnavailable, cancelled, timedOut, networkFailure, malformedResponse, httpStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .disabled: "Enable optional model assistance first."
        case .missingKey: "Add an API key for the selected provider."
        case .wifiRequired: "A non-metered Wi-Fi connection is required."
        case .busy: "A request is already in progress."
        case .quotaExceeded: "The daily limit of 20 requests has been reached."
        case .invalidInput: "Enter a scene of 1–1,000 characters and a valid model ID."
        case .invalidKey: "Enter a valid API key without whitespace."
        case .credentialsUnavailable: "The secure credential store is unavailable."
        case .cancelled: "The request was cancelled."
        case .timedOut: "The request timed out. Try again when you are ready."
        case .networkFailure: "The request could not be completed."
        case .malformedResponse: "The model returned an invalid or incomplete response."
        case .httpStatus(401): "The provider rejected the API key."
        case .httpStatus(429): "The provider's request limit was reached."
        case .httpStatus: "The provider could not complete the request."
        }
    }
}
