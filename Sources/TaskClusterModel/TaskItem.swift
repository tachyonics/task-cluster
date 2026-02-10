import Foundation

package struct TaskItem: Codable, Sendable, Equatable {
    package var taskId: UUID
    package var title: String
    package var description: String?
    package var priority: Int
    package var dueBy: Date?
    package var status: TaskStatus
    package var createdAt: Date
    package var updatedAt: Date

    package init(
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
