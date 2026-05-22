import Testing
@testable import ultramar

@Test func timingSummaryFullBreakdown() {
    let summary = CLITimingSummary(
        engine: "qwen",
        loadDurationMs: 42_100,
        inferenceDurationMs: 23_400,
        tokensGenerated: 847
    )

    #expect(summary.stderrLine == "Timing: load 42.1s | generate 23.4s (847 tokens, 36.2 tok/s) | total 65.5s")
    #expect(summary.totalDurationMs == 65_500)
    if case .int(let loadMs)? = summary.jsonFields["load_duration_ms"] {
        #expect(loadMs == 42_100)
    } else {
        Issue.record("Expected load_duration_ms")
    }
    if case .int(let totalMs)? = summary.jsonFields["total_duration_ms"] {
        #expect(totalMs == 65_500)
    } else {
        Issue.record("Expected total_duration_ms")
    }
    if case .double(let tps) = summary.jsonFields["tokens_per_second"] {
        #expect((tps - 36.2).magnitude < 0.05)
    } else {
        Issue.record("Expected tokens_per_second in JSON fields")
    }
}

@Test func timingSummaryWithoutLoad() {
    let summary = CLITimingSummary(
        engine: "appleFM",
        loadDurationMs: 0,
        inferenceDurationMs: 1_500,
        tokensGenerated: 0
    )

    #expect(summary.stderrLine == "Timing: generate 1.5s | total 1.5s")
    #expect(summary.jsonFields["tokens_per_second"] == nil)
}

@Test func timingSummaryZeroInferenceMsNoTokensPerSecond() {
    let summary = CLITimingSummary(
        engine: "qwen",
        loadDurationMs: 100,
        inferenceDurationMs: 0,
        tokensGenerated: 10
    )

    #expect(summary.jsonFields["tokens_per_second"] == nil)
    #expect(!summary.stderrLine.contains("tok/s"))
}

@Test func tokensPerSecondCalculation() {
    let tps = CLITimingSummary.tokensPerSecond(tokens: 100, inferenceMs: 2_000)
    #expect(tps == 50.0)
    #expect(CLITimingSummary.tokensPerSecond(tokens: 0, inferenceMs: 2_000) == nil)
    #expect(CLITimingSummary.tokensPerSecond(tokens: 10, inferenceMs: 0) == nil)
}
