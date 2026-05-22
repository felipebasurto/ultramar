import Foundation
import Testing
@testable import UltramarLLM

@Test func networkPolicyAllowsDownloadWhenCellularEnabled() throws {
    try NetworkPolicyChecker().assertDownloadAllowed(allowsCellular: true)
}

@Test func diskSpaceCheckerReadsNonNegativeCapacityForTempDirectory() {
    let temp = DiskSpaceChecker().availableBytes(at: FileManager.default.temporaryDirectory)
    #expect(temp >= 0)
}

@Test func installStateDefaultsToNotInstalled() {
    #expect(ModelInstallState.notInstalled.isInstalled == false)
    #expect(ModelInstallState.notInstalled.progressFraction == nil)
}
