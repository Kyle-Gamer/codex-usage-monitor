import CodexUsageMonitorCore
import Foundation

func runRateLimitLogicTests() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func window(_ kind: UsageWindowKind, remaining: Int, resetAfter: TimeInterval) -> UsageWindow {
        UsageWindow(
            id: kind.rawValue,
            kind: kind,
            durationMinutes: kind == .fiveHour ? 300 : 10_080,
            usedPercent: 100 - remaining,
            resetsAt: now.addingTimeInterval(resetAfter)
        )
    }

    check(RateLimitLogic.classify(durationMinutes: 300) == .fiveHour, "classifies 5-hour window")
    check(RateLimitLogic.classify(durationMinutes: 10_080) == .sevenDay, "classifies 7-day window")
    check(RateLimitLogic.classify(durationMinutes: 60) == .fiveHour, "classifies short rolling window")
    check(RateLimitLogic.classify(durationMinutes: 1_440) == .other, "classifies other window")
    check(RateLimitLogic.classify(durationMinutes: nil) == .other, "classifies unknown window")

    let fiveHour = window(.fiveHour, remaining: 40, resetAfter: 8_000)
    let sevenDay = window(.sevenDay, remaining: 40, resetAfter: 3_000)
    let tightest = RateLimitLogic.selectWindow(from: [fiveHour, sevenDay], mode: .tightest)
    check(tightest?.window.kind == .sevenDay, "tightest mode uses earliest reset as tie breaker")
    check(tightest?.usedFallback == false, "tightest mode is not a fallback")

    let other = UsageWindow(id: "other", kind: .other, durationMinutes: 30, usedPercent: 25, resetsAt: now.addingTimeInterval(300))
    let fallback = RateLimitLogic.selectWindow(from: [other], mode: .fiveHour)
    check(fallback?.window.id == "other", "fixed mode falls back to available window")
    check(fallback?.usedFallback == true, "fixed mode marks fallback")

    check(window(.fiveHour, remaining: 80, resetAfter: 0).severity == .normal, "normal severity")
    check(window(.fiveHour, remaining: 20, resetAfter: 0).severity == .warning, "warning severity")
    check(window(.fiveHour, remaining: 10, resetAfter: 0).severity == .critical, "critical severity")
    check(window(.fiveHour, remaining: 0, resetAfter: 0).remainingPercent == 0, "remaining percent is clamped")

    check(RateLimitLogic.formatCountdown(until: now.addingTimeInterval(2 * 60 * 60 + 14 * 60), now: now) == "2小时14分", "hour countdown")
    check(RateLimitLogic.formatCountdown(until: now.addingTimeInterval(4 * 24 * 60 * 60 + 23 * 60 * 60), now: now) == "4天23小时", "day countdown")
    check(RateLimitLogic.formatCountdown(until: now.addingTimeInterval(-1), now: now) == "现在", "expired countdown")
    check(RateLimitLogic.formatCountdown(until: nil, now: now) == "—", "missing countdown")

    let selected = SelectedWindow(window: window(.fiveHour, remaining: 68, resetAfter: 2_000), usedFallback: false)
    let staleTitle = RateLimitLogic.menuTitle(selected: selected, now: now, isStale: true)
    check(staleTitle.contains("5h") && staleTitle.contains("68%") && staleTitle.contains("离线"), "stale menu title")
}
