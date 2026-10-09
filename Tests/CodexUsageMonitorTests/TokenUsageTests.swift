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
    let formattingCases: [(Int64, String)] = [
        (0, "0"), (1, "1"), (999, "999"),
        (1_000, "1.0千"), (1_050, "1.1千"), (1_499, "1.5千"), (1_500, "1.5千"),
        (1_900, "1.9千"), (2_499, "2.5千"), (5_000, "5.0千"), (9_999, "10.0千"),
        (10_000, "1.0万"), (10_499, "1.0万"), (10_500, "1.1万"), (15_000, "1.5万"),
        (15_900, "1.6万"), (99_999, "10.0万"), (100_000, "10.0万"),
        (999_999, "100.0万"), (1_159_000, "115.9万")
    ]
    for (value, expected) in formattingCases {
        check(TokenUsageSnapshot.compact(value) == expected, "compact formatting for \(value) is \(expected)")
    }
    check(abs(TokenUsageSnapshot.estimatedAPICostUSD(for: 15_900) - 0.027825) < 0.0000001,
          "estimated price should use the original token count, not its rounded display")
}
