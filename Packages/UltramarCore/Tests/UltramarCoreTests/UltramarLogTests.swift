import Foundation
import Testing
@testable import UltramarCore

@Test func kvFormatsKeyValuePairs() {
    let formatted = UltramarLog.kv(("artifact", "qwen-brain"), ("bytes", 1234567))
    #expect(formatted == "artifact=qwen-brain bytes=1234567")
}

@Test func bytesLabelFormatsGigabytes() {
    #expect(UltramarLog.bytesLabel(2_700_000_000).contains("2.7"))
}

@Test func shaPrefixTruncatesDigest() {
    #expect(UltramarLog.shaPrefix("abcdef0123456789").count == 12)
}

@Test func singleLineCollapsesNewlines() {
    #expect(UltramarLog.singleLine("line one\nline two") == "line one line two")
}

@Test func logTimerMeasuresPositiveDuration() async throws {
    let start = ContinuousClock.now
    try await Task.sleep(for: .milliseconds(10))
    let durationMs = LogTimer.durationMilliseconds(since: start)
    #expect(durationMs >= 5)
}
