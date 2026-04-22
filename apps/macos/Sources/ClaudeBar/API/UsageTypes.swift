import Foundation

enum UsageStatus: String, Sendable {
    case ok
    case offline
    case rateLimited = "rate-limited"
    case unauthenticated
}

struct UsageBucket: Sendable, Equatable {
    var percent: Double
    var resetsAt: Date?
}

struct UsageSnapshot: Sendable, Equatable {
    var session: UsageBucket
    var weekly: UsageBucket
    var status: UsageStatus
    var fetchedAt: Date

    static func empty(status: UsageStatus) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageBucket(percent: 0, resetsAt: nil),
            weekly: UsageBucket(percent: 0, resetsAt: nil),
            status: status,
            fetchedAt: Date()
        )
    }
}
