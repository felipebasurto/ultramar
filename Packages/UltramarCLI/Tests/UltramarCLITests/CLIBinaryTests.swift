import Foundation
import Testing

@Test func cliHelpExitsZero() throws {
    let status = try runCLI(arguments: ["--help"])
    #expect(status == 0)
}

@Test func cliChatHelpMentionsBatchPrompts() throws {
    let output = try runCLIOutput(arguments: ["chat", "--help"])
    #expect(output.contains("--prompts-file"))
    #expect(output.contains("--system-prompt-file"))
    #expect(output.contains("--stdin-lines"))
    #expect(output.contains("--interactive"))
    #expect(output.contains("--backend"))
    #expect(output.contains("server"))
    #expect(output.contains("embedded"))
    #expect(output.contains("--base-url"))
}

@Test func routeToolLoopViaCLI() throws {
    let output = try runCLIOutput(arguments: ["route", "--task", "toolLoop", "--format", "json"])
    #expect(output.contains("edgeQwen"))
    #expect(output.contains("toolLoop"))
}

private func cliBinaryURL() -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let debug = packageRoot.appendingPathComponent(".build/debug/ultramar")
    if FileManager.default.fileExists(atPath: debug.path) {
        return debug
    }
    return packageRoot.appendingPathComponent(".build/release/ultramar")
}

@discardableResult
private func runCLI(arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = cliBinaryURL()
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

private func runCLIOutput(arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = cliBinaryURL()
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
