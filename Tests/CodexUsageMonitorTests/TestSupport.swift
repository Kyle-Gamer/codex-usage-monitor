import Foundation
import Darwin

struct TestFailure: Error {
    let message: String
}

@discardableResult
func check(_ condition: @autoclosure () -> Bool, _ name: String) -> Bool {
    guard condition() else {
        print("FAIL: \(name)")
        exit(1)
    }
    print("PASS: \(name)")
    return true
}
