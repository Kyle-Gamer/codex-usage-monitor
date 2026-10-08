import AppKit
import Foundation

enum CodexLocator {
    static let bundleIdentifier = "com.openai.codex"

    static func codexExecutableURL() -> URL? {
        var appURLs: [URL] = []
        if let workspaceURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            appURLs.append(workspaceURL)
        }
        appURLs.append(contentsOf: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/System/Applications/ChatGPT.app")
        ])

        for appURL in appURLs {
            let resourceURL = appURL.appendingPathComponent("Contents/Resources/codex")
            if FileManager.default.isExecutableFile(atPath: resourceURL.path) {
                return resourceURL
            }
        }

        let standalone = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/packages/standalone/current/bin/codex")
        if FileManager.default.isExecutableFile(atPath: standalone.path) {
            return standalone
        }
        return nil
    }
}
