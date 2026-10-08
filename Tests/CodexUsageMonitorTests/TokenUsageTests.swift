import CodexUsageMonitorCore
import Foundation

func runTokenUsageTests() throws {
    let json = #"{"summary":{"lifetimeTokens":2500000,"peakDailyTokens":1200000,"longestRunningTurnSec":90,"currentStreakDays":3,"longestStreakDays":5},"dailyUsageBuckets":[{"startDate":"2026-10-01","tokens":1000},{"startDate":"2026-10-08","tokens":1159000},{"startDate":"2026-09-30","tokens":500}]}"#
    let usage = try JSONDecoder().decode(TokenUsageSnapshot.self, from: Data(json.utf8))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
    check(usage.tokens(on: today, calendar: calendar) == 1_159_000, "today should match its daily bucket")
    check(usage.tokens(in: today, calendar: calendar) == 1_160_000, "month should aggregate current-month buckets")
    check(usage.summary.lifetimeTokens == 2_500_000, "summary fields should decode")
    check(TokenUsageSnapshot.compact(1_159_000) == "115.9万", "token compact format should use ten-thousands")
}
