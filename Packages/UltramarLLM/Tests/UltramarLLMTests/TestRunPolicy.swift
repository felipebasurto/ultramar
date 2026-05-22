import Foundation

/// Opt-in gates for expensive or networked tests. Default `make test-run` skips these.
enum TestRunPolicy {
    static var integrationTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["ULTRAMAR_INTEGRATION_TESTS"] == "1"
    }

    static var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["ULTRAMAR_NETWORK_TESTS"] == "1"
    }
}
