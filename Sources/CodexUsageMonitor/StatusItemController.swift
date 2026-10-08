import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let model: MonitorModel
    private let statusItem: NSStatusItem
    private let menuBarIcon: NSImage?
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(model: MonitorModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarIcon = Self.makeMenuBarIcon()
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "Codex 剩余用量"

        // Outside clicks are handled explicitly below. Using an application-
        // defined popover keeps button taps inside the panel from being treated
        // as a dismissal before SwiftUI can run their actions (notably reset
        // confirmation).
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 370, height: 620)
        popover.contentViewController = NSHostingController(rootView: MonitorMenuView(model: model))
        installOutsideClickMonitors()

        observation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refreshButton() }
        }
        refreshButton()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshButton()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let tokenSuffix = model.showDailyTokenUsage ? model.tokenUsage.map { " · \($0.todayFormatted)" } ?? "" : ""
        button.title = model.presentation.menuTitle + tokenSuffix
        let image = menuBarIcon ?? NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Codex 用量")
        image?.isTemplate = true
        button.image = image
        // Leave tinting to the menu bar appearance so the symbol and title adapt to light/dark mode.
        button.contentTintColor = nil
    }

    /// Draw the menu bar variant directly so the transparent background remains
    /// transparent when AppKit applies the template tint for light/dark mode.
    private static func makeMenuBarIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        icon.lockFocus()

        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: NSPoint(x: 9, y: 9),
            radius: 6.25,
            startAngle: -90,
            endAngle: 205,
            clockwise: false
        )
        ring.lineWidth = 1.8
        ring.lineCapStyle = .round
        NSColor.black.setStroke()
        ring.stroke()

        let brackets = NSBezierPath()
        brackets.move(to: NSPoint(x: 8, y: 6.3))
        brackets.line(to: NSPoint(x: 5.6, y: 9))
        brackets.line(to: NSPoint(x: 8, y: 11.7))
        brackets.move(to: NSPoint(x: 10, y: 6.3))
        brackets.line(to: NSPoint(x: 12.4, y: 9))
        brackets.line(to: NSPoint(x: 10, y: 11.7))
        brackets.lineWidth = 1.7
        brackets.lineCapStyle = .round
        brackets.lineJoinStyle = .round
        NSColor.black.setStroke()
        brackets.stroke()

        icon.unlockFocus()
        icon.isTemplate = true
        return icon
    }

    private func installOutsideClickMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            // Do not let the opening click close the popover immediately. The
            // status-item button is part of the local event stream as well.
            if let button = self?.statusItem.button,
               let statusWindow = button.window,
               event.window === statusWindow,
               button.frame.contains(event.locationInWindow) {
                return event
            }
            Task { @MainActor in
                self?.closePopoverIfClickIsOutside(event)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            Task { @MainActor in
                self?.closePopoverIfClickIsOutside(event)
            }
        }
    }

    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        guard popover.isShown else { return }
        let location = NSEvent.mouseLocation
        if let popoverWindow = popover.contentViewController?.view.window,
           popoverWindow.frame.contains(location) {
            return
        }
        if let button = statusItem.button,
           let statusWindow = button.window {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonRectOnScreen = statusWindow.convertToScreen(buttonRectInWindow)
            if buttonRectOnScreen.contains(location) {
                return
            }
        }
        popover.performClose(event)
    }

}
