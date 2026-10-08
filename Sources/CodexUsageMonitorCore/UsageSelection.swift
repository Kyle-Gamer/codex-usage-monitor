import Foundation

public struct UsagePresentation: Equatable, Sendable {
    public let selected: SelectedWindow?
    public let menuTitle: String
    public let isStale: Bool

    public init(snapshot: UsageSnapshot?, mode: DisplayMode, now: Date = Date(), isStale: Bool = false) {
        let selection = snapshot.flatMap { RateLimitLogic.selectWindow(from: $0.windows, mode: mode) }
        self.selected = selection
        self.menuTitle = RateLimitLogic.menuTitle(selected: selection, now: now, isStale: isStale)
        self.isStale = isStale
    }
}
