import Foundation

// MARK: - Task status

public enum TaskStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - Task domain model

public struct TaskItem: Codable, Sendable {
    public var taskId: UUID
    public var title: String
    public var description: String?
    public var priority: Int
    public var dueBy: Date?
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        taskId: UUID = UUID(),
        title: String,
        description: String? = nil,
        priority: Int,
        dueBy: Date? = nil,
        status: TaskStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.taskId = taskId
        self.title = title
        self.description = description
        self.priority = priority
        self.dueBy = dueBy
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

