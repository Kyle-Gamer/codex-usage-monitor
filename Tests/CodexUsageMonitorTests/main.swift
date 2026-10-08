import Foundation
import Darwin

do {
    try runRateLimitLogicTests()
    try runProtocolParserTests()
    try runTokenUsageTests()
    print("All Codex Usage Monitor tests passed.")
} catch let failure as TestFailure {
    print("FAIL: \(failure.message)")
    exit(1)
} catch {
    print("FAIL: \(error)")
    exit(1)
}
