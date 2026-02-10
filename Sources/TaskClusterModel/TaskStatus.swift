package enum TaskStatus: String, Codable, Sendable, Equatable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}
