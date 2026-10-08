import Foundation

public enum RateLimitLogic {
    public static func classify(durationMinutes: Int64?) -> UsageWindowKind {
        guard let durationMinutes else { return .other }
        if durationMinutes <= 6 * 60 { return .fiveHour }
        if durationMinutes >= 6 * 24 * 60 { return .sevenDay }
        return .other
    }

    public static func selectWindow(
        from windows: [UsageWindow],
        mode: DisplayMode
    ) -> SelectedWindow? {
        guard !windows.isEmpty else { return nil }

        let recognized = windows.filter { $0.kind == .fiveHour || $0.kind == .sevenDay }
        let candidates = recognized.isEmpty ? windows : recognized

        switch mode {
        case .tightest:
            return candidates
                .sorted {
                    if $0.remainingPercent != $1.remainingPercent {
                        return $0.remainingPercent < $1.remainingPercent
                    }
                    return ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture)
                }
                .first
                .map { SelectedWindow(window: $0, usedFallback: false) }
        case .fiveHour:
            if let exact = candidates.first(where: { $0.kind == .fiveHour }) {
                return SelectedWindow(window: exact, usedFallback: false)
            }
        case .sevenDay:
            if let exact = candidates.first(where: { $0.kind == .sevenDay }) {
                return SelectedWindow(window: exact, usedFallback: false)
            }
        }

        return candidates
            .sorted {
                if $0.remainingPercent != $1.remainingPercent {
                    return $0.remainingPercent < $1.remainingPercent
                }
                return ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture)
            }
            .first
            .map { SelectedWindow(window: $0, usedFallback: true) }
    }

    public static func formatCountdown(until resetDate: Date?, now: Date = Date()) -> String {
        guard let resetDate else { return "—" }
        let seconds = Int(resetDate.timeIntervalSince(now))
        if seconds <= 0 { return "现在" }
        let minutes = seconds / 60
        if minutes < 1 { return "不到 1 分钟" }
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let remainingMinutes = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天"
        }
        if hours > 0 {
            return remainingMinutes > 0 ? "\(hours)小时\(remainingMinutes)分" : "\(hours)小时"
        }
        return "\(remainingMinutes)分"
    }

    public static func menuTitle(
        selected: SelectedWindow?,
        now: Date = Date(),
        isStale: Bool = false
    ) -> String {
        guard let selected else { return isStale ? "Codex · 离线" : "Codex · …" }
        let window = selected.window
        let fallbackSuffix = selected.usedFallback ? "*" : ""
        let staleSuffix = isStale ? " · 离线" : ""
        return "\(window.kind.shortLabel)\(fallbackSuffix) \(window.remainingPercent)% · \(formatCountdown(until: window.resetsAt, now: now))\(staleSuffix)"
    }
}
