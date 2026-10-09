import CodexUsageMonitorCore
import SwiftUI

struct MonitorMenuView: View {
    @ObservedObject var model: MonitorModel
    @State private var pendingReset: PendingReset?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let selected = model.presentation.selected, selected.usedFallback {
                Label("设置的窗口暂时不可用，已回退显示 \(selected.window.kind.title)", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let snapshot = model.snapshot, !snapshot.windows.isEmpty {
                windows(snapshot.windows)
            } else {
                emptyState
            }
            tokenUsageSection
            if let resetCredits = model.resetCredits {
                resetCreditsSection(resetCredits)
            }
            if let resetFeedback = model.resetFeedback {
                Text(resetFeedback)
                    .font(.caption)
                    .foregroundStyle(resetFeedback.hasPrefix("重置失败") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            settings
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 370)
        .alert(item: $pendingReset) { pending in
            Alert(
                title: Text("确认重置 Codex 额度？"),
                message: Text(pending.confirmationMessage),
                primaryButton: .destructive(Text("确认重置")) {
                    model.consumeReset(creditID: pending.creditID)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Usage Monitor")
                    .font(.headline)
                Text(model.connectionStatus.title)
                    .font(.caption)
                    .foregroundStyle(model.isStale ? Color.secondary : Color.green)
            }
            Spacer()
            Text(model.presentation.menuTitle)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(color(for: model.presentation.selected?.window.severity, stale: model.isStale))
                .multilineTextAlignment(.trailing)
        }
    }

    private func windows(_ windows: [UsageWindow]) -> some View {
        VStack(spacing: 10) {
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(window.kind.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("剩余 \(window.remainingPercent)%")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(color(for: window.severity, stale: model.isStale))
                    }
                    ProgressView(value: Double(window.remainingPercent), total: 100)
                        .tint(color(for: window.severity, stale: model.isStale))
                    HStack {
                        Text("重置：\(window.resetsAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")")
                        Spacer()
                        Text(RateLimitLogic.formatCountdown(until: window.resetsAt, now: model.now))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func resetCreditsSection(_ summary: ResetCreditsSummary) -> some View {
        let details = summary.credits ?? []
        let hiddenCount = max(0, summary.availableCount - details.count)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("额度重置机会")
                        .font(.subheadline.weight(.semibold))
                    Text("使用后会同时刷新 5 小时和 7 天 Codex 窗口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("可用 \(summary.availableCount) 次")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            }

            if summary.availableCount == 0 {
                Text("当前没有可用的额度重置机会")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if details.isEmpty {
                resetCreditFallbackRow(title: "使用下一个可用重置", creditID: nil)
                Text("Codex 暂未提供这次机会的详细过期时间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(details) { credit in
                    resetCreditRow(credit)
                }
                if hiddenCount > 0 {
                    resetCreditFallbackRow(title: "使用下一个可用重置", creditID: nil)
                    Text("另有 \(hiddenCount) 次机会暂未提供详细信息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    private func resetCreditRow(_ credit: ResetCredit) -> some View {
        let usable = credit.isUsable(at: model.now) && credit.resetType == .codexRateLimits
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(usable ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(credit.displayTitle)
                    .font(.caption.weight(.semibold))
                if let expiresAt = credit.expiresAt {
                    Text(usable ? "过期：\(expiresAt.formatted(date: .abbreviated, time: .shortened)) · \(RateLimitLogic.formatCountdown(until: expiresAt, now: model.now))" : "已过期：\(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("不过期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let description = credit.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button("重置") {
                pendingReset = PendingReset(
                    id: credit.id,
                    creditID: credit.id,
                    title: credit.displayTitle,
                    expiresAt: credit.expiresAt
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!usable || model.isResetting)
        }
    }

    private func resetCreditFallbackRow(title: String, creditID: String?) -> some View {
        HStack {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
            Text("详细信息不可用时，Codex 会选择下一个可用机会")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("重置") {
                pendingReset = PendingReset(
                    id: "next-available",
                    creditID: creditID,
                    title: title,
                    expiresAt: nil
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isResetting)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isStale ? "暂时无法读取最新额度" : "正在读取 Codex 额度…")
                .font(.subheadline.weight(.semibold))
            Text(model.lastError ?? "保留上次成功数据后，会在连接恢复时自动更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("顶部显示")
                .font(.subheadline.weight(.semibold))
            Picker("顶部显示", selection: $model.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            Toggle("登录时自动启动", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Toggle("在状态栏显示今日 Token 用量", isOn: $model.showDailyTokenUsage)
        }
    }

    private var tokenUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token 活动")
                .font(.subheadline.weight(.semibold))
            if let usage = model.tokenUsage {
                metricRow("今日消耗", value: usage.tokens(on: model.now).map { "\(TokenUsageSnapshot.compact($0)) token · \(estimatedCost(for: $0))" } ?? "暂无数据")
                metricRow("本月消耗", value: usage.tokens(in: model.now).map { "\(TokenUsageSnapshot.compact($0)) token · \(estimatedCost(for: $0))" } ?? "暂无数据")
                if let lifetime = usage.summary.lifetimeTokens {
                    metricRow("累计消耗", value: "\(TokenUsageSnapshot.compact(lifetime)) token")
                }
                if let peak = usage.summary.peakDailyTokens {
                    metricRow("单日峰值", value: "\(TokenUsageSnapshot.compact(peak)) token")
                }
                Text("估价假设所有 Token 均按 gpt-5.3-codex 输入价（$1.75/百万）计算。官方个人资料未提供模型及输入/输出拆分，实际 API 等值金额可能不同；Codex 订阅不按此金额计费。今日与本月数据暂按本机日历日汇总。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Codex 尚未提供 Token 活动数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced).weight(.medium))
        }
        .font(.caption)
    }

    private func estimatedCost(for tokens: Int64) -> String {
        let cost = TokenUsageSnapshot.estimatedAPICostUSD(for: tokens)
        return cost < 0.01 ? String(format: "$%.4f (估算)", cost) : String(format: "$%.2f (估算)", cost)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("上次更新：\(model.lastUpdatedText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("额度每分钟自动更新；App Server 有推送时会即时同步")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Button("登录项设置") { model.openLoginItemsSettings() }
                Spacer()
                Button("退出") { model.quit() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func color(for severity: UsageSeverity?, stale: Bool) -> Color {
        if stale { return .secondary }
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        default: return .accentColor
        }
    }

    private struct PendingReset: Identifiable {
        let id: String
        let creditID: String?
        let title: String
        let expiresAt: Date?

        var confirmationMessage: String {
            let expiration = expiresAt.map {
                "\n\n这次机会过期时间：\($0.formatted(date: .abbreviated, time: .shortened))。"
            } ?? ""
            return "将消耗「\(title)」并刷新 5 小时和 7 天 Codex 用量窗口。该操作不可撤销。\(expiration)"
        }
    }
}
