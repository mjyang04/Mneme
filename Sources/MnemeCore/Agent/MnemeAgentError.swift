import Foundation

public enum MnemeAgentError: LocalizedError, Equatable {
    case invalidArgument(String)
    case missingIndex(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidArgument(message):
            message
        case let .missingIndex(path):
            "Mneme index not found at \(path). Open the Mneme app and run indexing first."
        case let .unsupported(message):
            message
        }
    }
}
