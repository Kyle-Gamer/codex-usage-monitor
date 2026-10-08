import Foundation

public enum DisplayMode: String, CaseIterable, Codable, Sendable {
    case tightest
    case fiveHour
    case sevenDay

    public var title: String {
        switch self {
        case .tightest: return "更紧张的额度"
        case .fiveHour: return "固定显示 5 小时额度"
        case .sevenDay: return "固定显示 7 天额度"
        }
    }
}

public enum UsageWindowKind: String, Codable, Sendable {
    case fiveHour
    case sevenDay
    case other

    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .other: return "额度"
        }
    }

    public var title: String {
        switch self {
        case .fiveHour: return "5 小时窗口"
        case .sevenDay: return "7 天窗口"
        case .other: return "其他窗口"
        }
    }
}

public enum UsageSeverity: String, Codable, Sendable {
    case normal
    case warning
    case critical
    case stale
}

public enum ResetCreditStatus: String, Codable, Sendable {
    case available
    case redeeming
    case redeemed
    case unknown

    public var title: String {
        switch self {
        case .available: return "可用"
        case .redeeming: return "处理中"
        case .redeemed: return "已使用"
        case .unknown: return "状态未知"
        }
    }
}

public enum ResetCreditType: String, Codable, Sendable {
    case codexRateLimits
    case unknown
}

public struct ResetCredit: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let resetType: ResetCreditType
    public let status: ResetCreditStatus
    public let grantedAt: Date
    public let expiresAt: Date?
    public let title: String?
    public let description: String?

    public init(
        id: String,
        resetType: ResetCreditType,
        status: ResetCreditStatus,
        grantedAt: Date,
        expiresAt: Date?,
        title: String?,
        description: String?
    ) {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.title = title
        self.description = description
    }

    public var displayTitle: String {
        title?.isEmpty == false ? title! : "Codex 全量重置"
    }

    public func isUsable(at date: Date = Date()) -> Bool {
        status == .available && (expiresAt == nil || expiresAt! > date)
    }
}

public struct ResetCreditsSummary: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let credits: [ResetCredit]?

    public init(availableCount: Int, credits: [ResetCredit]?) {
        self.availableCount = max(0, availableCount)
        self.credits = credits
    }

    public var availableCredits: [ResetCredit] {
        credits ?? []
    }
}

public enum ResetConsumptionResult: Equatable, Sendable {
    case reset
    case nothingToReset
    case noCredit
    case alreadyRedeemed
    case failed(String)
}

public struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: UsageWindowKind
    public let durationMinutes: Int64?
    public let usedPercent: Int
    public let resetsAt: Date?

    public init(
        id: String,
        kind: UsageWindowKind,
        durationMinutes: Int64?,
        usedPercent: Int,
        resetsAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.durationMinutes = durationMinutes
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }

    public var severity: UsageSeverity {
        Self.severity(forRemainingPercent: remainingPercent)
    }

    public static func severity(forRemainingPercent remaining: Int) -> UsageSeverity {
        switch remaining {
        case ...10: return .critical
        case 11...20: return .warning
        default: return .normal
        }
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let windows: [UsageWindow]
    public let fetchedAt: Date
    public let planType: String?
    public let limitName: String?
    public let resetCredits: ResetCreditsSummary?

    private enum CodingKeys: String, CodingKey {
        case windows
        case fetchedAt
        case planType
        case limitName
        case resetCredits
    }

    public init(
        windows: [UsageWindow],
        fetchedAt: Date = Date(),
        planType: String? = nil,
        limitName: String? = nil,
        resetCredits: ResetCreditsSummary? = nil
    ) {
        self.windows = windows.sorted { lhs, rhs in
            let left = lhs.durationMinutes ?? Int64.max
            let right = rhs.durationMinutes ?? Int64.max
            return left < right
        }
        self.fetchedAt = fetchedAt
        self.planType = planType
        self.limitName = limitName
        self.resetCredits = resetCredits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            windows: try container.decode([UsageWindow].self, forKey: .windows),
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt),
            planType: try container.decodeIfPresent(String.self, forKey: .planType),
            limitName: try container.decodeIfPresent(String.self, forKey: .limitName),
            resetCredits: try container.decodeIfPresent(ResetCreditsSummary.self, forKey: .resetCredits)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windows, forKey: .windows)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(planType, forKey: .planType)
        try container.encodeIfPresent(limitName, forKey: .limitName)
        try container.encodeIfPresent(resetCredits, forKey: .resetCredits)
    }

    public var fiveHour: UsageWindow? {
        windows.first { $0.kind == .fiveHour }
    }

    public var sevenDay: UsageWindow? {
        windows.first { $0.kind == .sevenDay }
    }
}

public struct SelectedWindow: Equatable, Sendable {
    public let window: UsageWindow
    public let usedFallback: Bool

    public init(window: UsageWindow, usedFallback: Bool) {
        self.window = window
        self.usedFallback = usedFallback
    }
}

public enum ConnectionStatus: Equatable, Sendable {
    case starting
    case connected
    case reconnecting
    case offline(String)
    case unavailable(String)

    public var isStale: Bool {
        switch self {
        case .connected, .starting, .reconnecting: return false
        case .offline, .unavailable: return true
        }
    }

    public var title: String {
        switch self {
        case .starting: return "正在连接"
        case .connected: return "已连接"
        case .reconnecting: return "正在重连"
        case .offline: return "暂时离线"
        case .unavailable: return "未找到 Codex"
        }
    }
}

public struct CachedUsage: Codable, Equatable, Sendable {
    public let snapshot: UsageSnapshot
    public let savedAt: Date

    public init(snapshot: UsageSnapshot, savedAt: Date = Date()) {
        self.snapshot = snapshot
        self.savedAt = savedAt
    }
}

public struct TokenUsageDailyBucket: Codable, Equatable, Sendable, Identifiable {
    public let startDate: String
    public let tokens: Int64
    public var id: String { startDate }
}

public struct TokenUsageSummary: Codable, Equatable, Sendable {
    public let lifetimeTokens: Int64?
    public let peakDailyTokens: Int64?
    public let longestRunningTurnSec: Int64?
    public let currentStreakDays: Int64?
    public let longestStreakDays: Int64?
}

public struct TokenUsageSnapshot: Codable, Equatable, Sendable {
    public let summary: TokenUsageSummary
    public let dailyUsageBuckets: [TokenUsageDailyBucket]?

    public func tokens(on date: Date, calendar: Calendar = .current) -> Int64? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)
        guard let buckets = dailyUsageBuckets,
              let bucket = buckets.first(where: { $0.startDate == key }) else { return nil }
        return bucket.tokens
    }

    public func tokens(in month: Date, calendar: Calendar = .current) -> Int64? {
        guard let buckets = dailyUsageBuckets,
              let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let values = buckets.filter { bucket in
            guard let date = formatter.date(from: bucket.startDate) else { return false }
            return interval.contains(date)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(Int64(0)) { $0 + $1.tokens }
    }

    public var todayFormatted: String {
        let now = Date()
        guard let amount = tokens(on: now) else { return "Token 暂不可用" }
        let estimatedCost = Double(amount) * 1.75 / 1_000_000
        return "\(Self.compact(amount)) token $\(String(format: "%.2f", estimatedCost))"
    }

    public static func compact(_ tokens: Int64) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1f万", Double(tokens) / 10_000)
        }
        if tokens >= 10_000 { return "\(tokens / 10_000)万" }
        if tokens >= 1_000 { return String(format: "%.1f千", Double(tokens) / 1_000) }
        return "\(tokens)"
    }
}
