import CodexUsageMonitorCore
import Foundation

func runProtocolParserTests() throws {
    let json = """
    {"id":2,"result":{"rateLimits":{"planType":"prolite","primary":{"usedPercent":50,"windowDurationMins":300,"resetsAt":1700000300}},"rateLimitsByLimitId":{"codex":{"limitName":"Codex","primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1700000900}},"codex_bengalfox":{"limitName":"Spark","primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1700000300}}}}}
    """.data(using: .utf8)!

    guard case .snapshot(let snapshot) = ProtocolParser.parse(json, at: Date(timeIntervalSince1970: 1_700_000_000)) else {
        throw TestFailure(message: "expected a complete snapshot")
    }
    check(snapshot.windows.count == 1, "parser ignores Spark bucket")
    check(snapshot.windows.first?.kind == .sevenDay, "parser classifies codex bucket")
    check(snapshot.windows.first?.remainingPercent == 88, "parser calculates remaining percent")
    check(snapshot.limitName == "Codex", "parser keeps Codex limit name")

    let update = """
    {"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":20}}}}
    """.data(using: .utf8)!
    guard case .update(let sparse) = ProtocolParser.parse(update, previous: snapshot) else {
        throw TestFailure(message: "expected a sparse update")
    }
    check(sparse.windows.count == 1, "sparse update keeps existing secondary state")
    check(sparse.windows.first?.usedPercent == 20, "sparse update replaces changed field")

    let twoWindowJSON = """
    {"id":3,"result":{"rateLimits":{"primary":{"usedPercent":72,"windowDurationMins":300,"resetsAt":1700000300},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1700000900}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":72,"windowDurationMins":300,"resetsAt":1700000300},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1700000900}}}}}
    """.data(using: .utf8)!
    guard case .snapshot(let twoWindowSnapshot) = ProtocolParser.parse(twoWindowJSON) else {
        throw TestFailure(message: "expected both windows")
    }
    check(twoWindowSnapshot.fiveHour?.remainingPercent == 28, "parser restores 5-hour window")
    check(twoWindowSnapshot.sevenDay?.remainingPercent == 80, "parser keeps 7-day window alongside 5-hour window")

    let resetJSON = """
    {"id":4,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":90,"windowDurationMins":10080,"resetsAt":1700000900}},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"reset-1","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":1701000000,"title":"Full reset","description":"One free reset"}]}}}
    """.data(using: .utf8)!
    guard case .snapshot(let resetSnapshot) = ProtocolParser.parse(resetJSON) else {
        throw TestFailure(message: "expected reset credit details")
    }
    check(resetSnapshot.resetCredits?.availableCount == 1, "parser reads reset credit count")
    check(resetSnapshot.resetCredits?.credits?.first?.displayTitle == "Full reset", "parser reads reset credit title")
    check(resetSnapshot.resetCredits?.credits?.first?.resetType == .codexRateLimits, "parser reads reset credit type")
    check(resetSnapshot.resetCredits?.credits?.first?.expiresAt != nil, "parser reads reset credit expiration")

    let resetUpdate = """
    {"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":91}}}}
    """.data(using: .utf8)!
    guard case .update(let resetSparseUpdate) = ProtocolParser.parse(resetUpdate, previous: resetSnapshot) else {
        throw TestFailure(message: "expected reset-aware sparse update")
    }
    check(resetSparseUpdate.resetCredits?.availableCount == 1, "sparse update keeps reset credit details")

    let consumeJSON = """
    {"id":5,"result":{"outcome":"reset"}}
    """.data(using: .utf8)!
    guard case .reset(.reset) = ProtocolParser.parse(consumeJSON) else {
        throw TestFailure(message: "expected reset outcome")
    }

    let unknownOutcomeJSON = """
    {"id":6,"result":{"outcome":"futureOutcome"}}
    """.data(using: .utf8)!
    guard case .reset(.failed(let message)) = ProtocolParser.parse(unknownOutcomeJSON) else {
        throw TestFailure(message: "expected unknown reset outcome to be reported")
    }
    check(message.contains("futureOutcome"), "unknown reset outcome keeps server value")
}
