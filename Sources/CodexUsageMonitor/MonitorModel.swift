import CodexUsageMonitorCore
import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var tokenUsage: TokenUsageSnapshot?
    @Published private(set) var connectionStatus: ConnectionStatus = .starting
    @Published private(set) var now = Date()
    @Published private(set) var lastError: String?
    @Published private(set) var resetFeedback: String?
    @Published private(set) var isResetting = false
    @Published private(set) var launchAtLogin: Bool
    @Published var showDailyTokenUsage: Bool {
        didSet { UserDefaults.standard.set(showDailyTokenUsage, forKey: Keys.showDailyTokenUsage) }
    }
    @Published var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Keys.displayMode)
        }
    }

    private let client: AppServerClient
    private var countdownTimer: Timer?
    private var refreshTimer: Timer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let displayMode = "displayMode"
        static let launchAtLogin = "launchAtLogin"
        static let cachedUsage = "cachedUsage"
        static let showDailyTokenUsage = "showDailyTokenUsage"
    }

    init() {
        let defaults = UserDefaults.standard
        let rawMode = defaults.string(forKey: Keys.displayMode) ?? DisplayMode.tightest.rawValue
        displayMode = DisplayMode(rawValue: rawMode) ?? .tightest
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? true
        showDailyTokenUsage = defaults.bool(forKey: Keys.showDailyTokenUsage)
        resetFeedback = nil
        client = AppServerClient(executableURL: CodexLocator.codexExecutableURL())

        if let data = defaults.data(forKey: Keys.cachedUsage), let cached = try? decoder.decode(CachedUsage.self, from: data) {
            snapshot = cached.snapshot
        }

        client.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.receive(snapshot) }
        }
        client.onTokenUsage = { [weak self] usage in
            Task { @MainActor in self?.tokenUsage = usage }
        }
        client.onStatus = { [weak self] status in
            Task { @MainActor in self?.receive(status) }
        }
        client.onResetResult = { [weak self] result in
            Task { @MainActor in self?.receive(result) }
        }
    }

    var isStale: Bool {
        connectionStatus.isStale || (snapshot.map { Date().timeIntervalSince($0.fetchedAt) > 10 * 60 } ?? false)
    }

    var presentation: UsagePresentation {
        UsagePresentation(snapshot: snapshot, mode: displayMode, now: now, isStale: isStale)
    }

    var resetCredits: ResetCreditsSummary? {
        snapshot?.resetCredits
    }

    var lastUpdatedText: String {
        guard let fetchedAt = snapshot?.fetchedAt else { return "尚未成功读取" }
        return fetchedAt.formatted(date: .omitted, time: .shortened)
    }

    func start() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        // The App Server also pushes updates; this one-minute poll is a lightweight calibration fallback.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.client.requestTokenUsage()
            }
        }
        if launchAtLogin && !LoginItemManager.isEnabled {
            do {
                try LoginItemManager.setEnabled(true)
            } catch {
                lastError = "登录启动尚未启用：\(error.localizedDescription)"
            }
        }
        client.start()
    }

    func refresh() {
        client.requestRateLimits()
    }

    func consumeReset(creditID: String?) {
        guard !isResetting else { return }
        isResetting = true
        resetFeedback = "正在提交额度重置…"
        client.consumeRateLimitReset(creditID: creditID)
    }

    func receive(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        connectionStatus = .connected
        lastError = nil
        let cached = CachedUsage(snapshot: snapshot)
        if let data = try? encoder.encode(cached) {
            UserDefaults.standard.set(data, forKey: Keys.cachedUsage)
        }
    }

    func receive(_ status: ConnectionStatus) {
        connectionStatus = status
        if case .offline(let message) = status {
            lastError = message
        } else if case .unavailable(let message) = status {
            lastError = message
        }
    }

    func receive(_ result: ResetConsumptionResult) {
        isResetting = false
        switch result {
        case .reset:
            resetFeedback = "额度已重置，正在同步新的 5 小时和 7 天窗口…"
        case .alreadyRedeemed:
            resetFeedback = "这次重置已经处理过，正在同步最新额度…"
        case .nothingToReset:
            resetFeedback = "当前没有可重置的额度窗口，重置机会未消耗。"
        case .noCredit:
            resetFeedback = "没有可用的额度重置机会，可能已过期或已使用。"
        case .failed(let message):
            resetFeedback = "重置失败：\(message)"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            launchAtLogin = enabled
            UserDefaults.standard.set(enabled, forKey: Keys.launchAtLogin)
            lastError = nil
        } catch {
            lastError = "无法更新登录启动：\(error.localizedDescription)"
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    func openLoginItemsSettings() {
        LoginItemManager.openSettings()
    }

    func quit() {
        countdownTimer?.invalidate()
        refreshTimer?.invalidate()
        client.stop()
        NSApp.terminate(nil)
    }
}
