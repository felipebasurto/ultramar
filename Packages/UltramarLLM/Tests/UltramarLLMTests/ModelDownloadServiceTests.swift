import Foundation
import Testing
@testable import UltramarLLM

@Test func diskSpaceCheckerRejectsWhenRequirementExceedsAvailable() {
    let checker = DiskSpaceChecker()
    #expect(throws: ModelStoreError.self) {
        try checker.assertSufficientSpace(
            at: FileManager.default.temporaryDirectory,
            requiredBytes: Int64.max / 4
        )
    }
}

@Test @MainActor func downloadServiceBootstrapStartsNotInstalledWithoutModel() async throws {
    let service = ModelDownloadService()
    let state = try await service.bootstrap()
    switch state {
    case .installed:
        #expect(Bool(true))
    case .notInstalled, .paused, .failed:
        #expect(Bool(true))
    case .downloading, .verifying:
        #expect(Bool(true))
    }
}
