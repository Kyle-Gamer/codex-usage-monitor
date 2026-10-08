import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: MonitorModel?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = MonitorModel()
        self.model = model
        statusItemController = StatusItemController(model: model)
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
