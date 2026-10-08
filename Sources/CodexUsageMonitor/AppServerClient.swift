import CodexUsageMonitorCore
import Foundation

final class AppServerClient: @unchecked Sendable {
    typealias SnapshotHandler = (UsageSnapshot) -> Void
    typealias TokenUsageHandler = (TokenUsageSnapshot) -> Void
    typealias StatusHandler = (ConnectionStatus) -> Void
    typealias ResetHandler = (ResetConsumptionResult) -> Void

    var onSnapshot: SnapshotHandler?
    var onTokenUsage: TokenUsageHandler?
    var onStatus: StatusHandler?
    var onResetResult: ResetHandler?

    private let executableURL: URL?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var outputBuffer = ""
    private var nextRequestID = 1
    private var initializeRequestID: Int?
    private var tokenUsageRequestID: Int?
    private var didInitialize = false
    private var isStopping = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var latestSnapshot: UsageSnapshot?
    private var requestTimeoutWorkItem: DispatchWorkItem?
    private var resetTimeoutWorkItem: DispatchWorkItem?
    private var rateLimitRequestInFlight = false
    private var resetRequestID: Int?
    private var resetRequestInFlight = false
    private var resetIdempotencyKey: String?
    private let outputQueue = DispatchQueue(label: "dev.codexusagemonitor.app-server-output")

    init(executableURL: URL?) {
        self.executableURL = executableURL
    }

    func start() {
        reconnectWorkItem?.cancel()
        guard process == nil else {
            requestRateLimits()
            return
        }
        guard let executableURL else {
            emitStatus(.unavailable("没有找到 ChatGPT 内置 Codex"))
            return
        }

        isStopping = false
        didInitialize = false
        outputBuffer = ""
        emitStatus(.starting)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        let inputPipe = process.standardInput as? Pipe
        let outputPipe = process.standardOutput as? Pipe
        let errorPipe = process.standardError as? Pipe
        self.input = inputPipe?.fileHandleForWriting
        self.output = outputPipe?.fileHandleForReading
        self.errorOutput = errorPipe?.fileHandleForReading
        self.process = process

        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.outputQueue.async { [weak self] in
                self?.consume(data)
            }
        }
        errorOutput?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.debug("app-server stderr \(data.count) bytes")
        }
        process.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        do {
            try process.run()
            let requestID = send(method: "initialize", params: [
                "clientInfo": [
                    "name": "Codex Usage Monitor",
                    "title": "Codex Usage Monitor",
                    "version": "1.0.0"
                ],
                "capabilities": ["experimentalApi": true]
            ])
            initializeRequestID = requestID
        } catch {
            self.process = nil
            emitStatus(.offline(error.localizedDescription))
            scheduleReconnect()
        }
    }

    func stop() {
        isStopping = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        output?.readabilityHandler = nil
        errorOutput?.readabilityHandler = nil
        requestTimeoutWorkItem?.cancel()
        resetTimeoutWorkItem?.cancel()
        rateLimitRequestInFlight = false
        resetRequestID = nil
        resetRequestInFlight = false
        if let process, process.isRunning {
            process.terminate()
        }
        input = nil
        output = nil
        errorOutput = nil
        self.process = nil
    }

    func requestRateLimits() {
        guard didInitialize, process?.isRunning == true, !rateLimitRequestInFlight else { return }
        rateLimitRequestInFlight = true
        let requestID = send(method: "account/rateLimits/read")
        requestTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            self?.rateLimitRequestInFlight = false
            self?.emitStatus(.offline("额度读取超时，等待下一次自动重试"))
        }
        requestTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        debug("rate limit request id=\(requestID)")
    }

    func requestTokenUsage() {
        guard didInitialize, process?.isRunning == true, tokenUsageRequestID == nil else { return }
        let requestID = send(method: "account/usage/read")
        tokenUsageRequestID = requestID
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.tokenUsageRequestID == requestID else { return }
            self.tokenUsageRequestID = nil
        }
    }

    func consumeRateLimitReset(creditID: String?) {
        guard didInitialize, process?.isRunning == true else {
            emitResetResult(.failed("Codex 尚未连接，暂时无法重置额度"))
            return
        }
        guard !resetRequestInFlight else { return }

        let idempotencyKey = resetIdempotencyKey ?? UUID().uuidString
        resetIdempotencyKey = idempotencyKey
        var params: [String: Any] = ["idempotencyKey": idempotencyKey]
        if let creditID {
            params["creditId"] = creditID
        }

        resetRequestInFlight = true
        let requestID = send(method: "account/rateLimitResetCredit/consume", params: params)
        resetRequestID = requestID
        resetTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.resetRequestID == requestID else { return }
            self.resetRequestID = nil
            self.resetRequestInFlight = false
            // Keep the key so a user retry is idempotent if the backend completed
            // the reset after the local request timed out.
            self.emitResetResult(.failed("额度重置请求超时；请先刷新确认结果，再决定是否重试"))
        }
        resetTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        debug("reset request id=\(requestID) credit=\(creditID ?? "next")")
    }

    private func send(method: String, params: [String: Any]? = nil) -> Int {
        let id = nextRequestID
        nextRequestID += 1
        var object: [String: Any] = ["id": id, "method": method]
        if let params { object["params"] = params }
        if params == nil, method == "account/rateLimits/read" {
            object["params"] = NSNull()
        }
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else {
            return id
        }
        var newlineData = data
        newlineData.append(0x0A)
        do {
            try input?.write(contentsOf: newlineData)
            debug("sent \(method) id=\(id)")
        } catch {
            emitStatus(.offline(error.localizedDescription))
        }
        return id
    }

    private func consume(_ data: Data) {
        outputBuffer.append(String(decoding: data, as: UTF8.self))
        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
            handleMessage(lineData)
        }
    }

    private func handleMessage(_ data: Data) {
        debug("received \(data.count) bytes")
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let method = object["method"] as? String ?? "-"
            let id = object["id"].map { String(describing: $0) } ?? "-"
            let resultKeys = (object["result"] as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "-"
            debug("message id=\(id) method=\(method) resultKeys=\(resultKeys)")
            if let responseID = object["id"] as? Int, responseID == resetRequestID {
                handleResetResponse(object)
                return
            }
            if object["error"] != nil {
                if let responseID = object["id"] as? Int, responseID == tokenUsageRequestID {
                    tokenUsageRequestID = nil
                    return
                }
                requestTimeoutWorkItem?.cancel()
                requestTimeoutWorkItem = nil
                rateLimitRequestInFlight = false
                emitStatus(.offline("Codex 暂时无法返回额度，稍后会自动重试"))
                return
            }
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseID = object["id"] as? Int,
           responseID == initializeRequestID,
           object["result"] != nil {
            didInitialize = true
            _ = sendNotification(method: "initialized")
            debug("initialized")
            emitStatus(.connected)
            requestRateLimits()
            requestTokenUsage()
            return
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseID = object["id"] as? Int,
           responseID == tokenUsageRequestID {
            tokenUsageRequestID = nil
            guard let result = object["result"] as? [String: Any],
                  let payload = try? JSONSerialization.data(withJSONObject: result),
                  let usage = try? JSONDecoder().decode(TokenUsageSnapshot.self, from: payload) else { return }
            DispatchQueue.main.async { [weak self] in self?.onTokenUsage?(usage) }
            return
        }
        guard let parsed = ProtocolParser.parse(data, previous: latestSnapshot) else {
            debug("ignored non-rate-limit message")
            return
        }
        switch parsed {
        case .snapshot(let snapshot), .update(let snapshot):
            rateLimitRequestInFlight = false
            requestTimeoutWorkItem?.cancel()
            requestTimeoutWorkItem = nil
            latestSnapshot = snapshot
            DispatchQueue.main.async { [weak self] in
                self?.onSnapshot?(snapshot)
                self?.onStatus?(.connected)
            }
        case .reset(let result):
            finishResetRequest(with: result)
        }
    }

    private func handleResetResponse(_ object: [String: Any]) {
        guard let responseID = object["id"] as? Int, responseID == resetRequestID else { return }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex 拒绝了这次额度重置"
            finishResetRequest(with: .failed(message))
            return
        }
        guard let result = object["result"] as? [String: Any],
              let outcome = result["outcome"] as? String else {
            finishResetRequest(with: .failed("Codex 返回了无法识别的重置结果"))
            return
        }
        finishResetRequest(with: Self.resetResult(from: outcome))
    }

    private func finishResetRequest(with result: ResetConsumptionResult) {
        guard resetRequestInFlight else { return }
        resetTimeoutWorkItem?.cancel()
        resetTimeoutWorkItem = nil
        resetRequestID = nil
        resetRequestInFlight = false
        resetIdempotencyKey = nil
        emitResetResult(result)
        requestRateLimits()
    }

    private func emitResetResult(_ result: ResetConsumptionResult) {
        DispatchQueue.main.async { [weak self] in
            self?.onResetResult?(result)
        }
    }

    private static func resetResult(from outcome: String) -> ResetConsumptionResult {
        switch outcome {
        case "reset": return .reset
        case "nothingToReset": return .nothingToReset
        case "noCredit": return .noCredit
        case "alreadyRedeemed": return .alreadyRedeemed
        default: return .failed("Codex 返回了未知的重置结果：\(outcome)")
        }
    }

    private func sendNotification(method: String, params: [String: Any]? = nil) -> Bool {
        var object: [String: Any] = ["method": method]
        if let params { object["params"] = params }
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else {
            return false
        }
        var newlineData = data
        newlineData.append(0x0A)
        do {
            try input?.write(contentsOf: newlineData)
            return true
        } catch {
            emitStatus(.offline(error.localizedDescription))
            return false
        }
    }

    private func handleTermination() {
        let resetWasInFlight = resetRequestInFlight
        output?.readabilityHandler = nil
        errorOutput?.readabilityHandler = nil
        input = nil
        output = nil
        errorOutput = nil
        process = nil
        didInitialize = false
        rateLimitRequestInFlight = false
        resetRequestID = nil
        resetRequestInFlight = false
        resetTimeoutWorkItem?.cancel()
        resetTimeoutWorkItem = nil
        if resetWasInFlight {
            emitResetResult(.failed("Codex 连接中断，重置结果未知；请先等待连接恢复并刷新额度"))
        }
        guard !isStopping else { return }
        emitStatus(.reconnecting)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isStopping, reconnectWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.start()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func emitStatus(_ status: ConnectionStatus) {
        debug("status \(status.title)")
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(status)
        }
    }

    private func debug(_ message: String) {
        guard ProcessInfo.processInfo.environment["CODEX_USAGE_MONITOR_DEBUG"] == "1" else { return }
        fputs("[CodexUsageMonitor] \(message)\n", stderr)
    }
}
