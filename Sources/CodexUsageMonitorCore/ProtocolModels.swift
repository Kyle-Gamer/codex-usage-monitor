import Foundation

struct JSONRPCEnvelope: Decodable {
    let id: Int?
    let method: String?
    let result: RateLimitResult?
    let params: RateLimitNotificationParams?
}

struct RateLimitResult: Decodable {
    let rateLimits: RateLimitSnapshotDTO?
    let rateLimitsByLimitId: [String: RateLimitSnapshotDTO]?
    let rateLimitResetCredits: RateLimitResetCreditsDTO?
    let outcome: String?
}

struct RateLimitNotificationParams: Decodable {
    let rateLimits: RateLimitSnapshotDTO
}

struct RateLimitSnapshotDTO: Decodable {
    let credits: CreditsDTO?
    let individualLimit: SpendControlDTO?
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindowDTO?
    let secondary: RateLimitWindowDTO?
    let rateLimitReachedType: String?

    func merging(with old: RateLimitSnapshotDTO?) -> RateLimitSnapshotDTO {
        RateLimitSnapshotDTO(
            credits: credits ?? old?.credits,
            individualLimit: individualLimit ?? old?.individualLimit,
            limitId: limitId ?? old?.limitId,
            limitName: limitName ?? old?.limitName,
            planType: planType ?? old?.planType,
            primary: primary ?? old?.primary,
            secondary: secondary ?? old?.secondary,
            rateLimitReachedType: rateLimitReachedType ?? old?.rateLimitReachedType
        )
    }

    init(
        credits: CreditsDTO?,
        individualLimit: SpendControlDTO?,
        limitId: String?,
        limitName: String?,
        planType: String?,
        primary: RateLimitWindowDTO?,
        secondary: RateLimitWindowDTO?,
        rateLimitReachedType: String?
    ) {
        self.credits = credits
        self.individualLimit = individualLimit
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.rateLimitReachedType = rateLimitReachedType
    }

    func usageSnapshot(at date: Date, resetCredits: ResetCreditsSummary? = nil) -> UsageSnapshot {
        var windows: [UsageWindow] = []
        if let primary {
            windows.append(primary.usageWindow(id: "primary"))
        }
        if let secondary {
            windows.append(secondary.usageWindow(id: "secondary"))
        }
        return UsageSnapshot(
            windows: windows,
            fetchedAt: date,
            planType: planType,
            limitName: limitName,
            resetCredits: resetCredits
        )
    }
}

struct RateLimitResetCreditsDTO: Decodable {
    let availableCount: Int64
    let credits: [RateLimitResetCreditDTO]?

    func resetCredits() -> ResetCreditsSummary {
        ResetCreditsSummary(
            availableCount: Int(clamping: availableCount),
            credits: credits?.map { $0.resetCredit() }
        )
    }
}

struct RateLimitResetCreditDTO: Decodable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: Int64
    let expiresAt: Int64?
    let title: String?
    let description: String?

    func resetCredit() -> ResetCredit {
        ResetCredit(
            id: id,
            resetType: ResetCreditType(rawValue: resetType) ?? .unknown,
            status: ResetCreditStatus(rawValue: status) ?? .unknown,
            grantedAt: Date(timeIntervalSince1970: TimeInterval(grantedAt)),
            expiresAt: expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            title: title,
            description: description
        )
    }
}

struct RateLimitWindowDTO: Decodable {
    let resetsAt: Int64?
    let usedPercent: Int
    let windowDurationMins: Int64?

    func usageWindow(id: String) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: RateLimitLogic.classify(durationMinutes: windowDurationMins),
            durationMinutes: windowDurationMins,
            usedPercent: usedPercent,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

struct CreditsDTO: Decodable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool
}

struct SpendControlDTO: Decodable {
    let limit: String
    let remainingPercent: Int
    let resetsAt: Int64
    let used: String
}

public enum ProtocolParser {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    public static func parse(_ data: Data, at date: Date = Date(), previous: UsageSnapshot? = nil) -> ParsedProtocolMessage? {
        guard let envelope = try? decoder.decode(JSONRPCEnvelope.self, from: data) else { return nil }
        if let result = envelope.result {
            if let outcome = result.outcome {
                return .reset(ResetConsumptionResult.fromWire(outcome))
            }
            guard let rateLimits = result.rateLimits else { return nil }
            let preferred = result.rateLimitsByLimitId?["codex"] ?? rateLimits
            return .snapshot(
                preferred.usageSnapshot(
                    at: date,
                    resetCredits: result.rateLimitResetCredits?.resetCredits()
                )
            )
        }
        if envelope.method == "account/rateLimits/updated", let params = envelope.params {
            let update = params.rateLimits
            let oldWindows = previous?.windows ?? []
            let primary = update.primary?.usageWindow(id: "primary") ?? oldWindows.first(where: { $0.id == "primary" })
            let secondary = update.secondary?.usageWindow(id: "secondary") ?? oldWindows.first(where: { $0.id == "secondary" })
            let mergedWindows = [primary, secondary].compactMap { $0 }
            return .update(
                UsageSnapshot(
                    windows: mergedWindows,
                    fetchedAt: date,
                    planType: previous?.planType,
                    limitName: previous?.limitName,
                    resetCredits: previous?.resetCredits
                )
            )
        }
        return nil
    }
}

public enum ParsedProtocolMessage {
    case snapshot(UsageSnapshot)
    case update(UsageSnapshot)
    case reset(ResetConsumptionResult)
}

private extension ResetConsumptionResult {
    static func fromWire(_ outcome: String) -> ResetConsumptionResult {
        switch outcome {
        case "reset": return .reset
        case "nothingToReset": return .nothingToReset
        case "noCredit": return .noCredit
        case "alreadyRedeemed": return .alreadyRedeemed
        default: return .failed("Codex 返回了未知的重置结果：\(outcome)")
        }
    }
}
