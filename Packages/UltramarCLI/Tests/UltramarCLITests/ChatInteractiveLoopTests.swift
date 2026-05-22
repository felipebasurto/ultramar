import Foundation
import Testing
@testable import ultramar

@Test func chatInteractiveLoopDetectsExitCommands() {
    #expect(ChatInteractiveLoop.isExitCommand("/exit"))
    #expect(ChatInteractiveLoop.isExitCommand("/quit"))
    #expect(ChatInteractiveLoop.isExitCommand("/q"))
    #expect(!ChatInteractiveLoop.isExitCommand("hola"))
}

@Test func chatInteractiveLoopStartsWhenExplicitFlagSet() {
    #expect(ChatInteractiveLoop.shouldRun(interactiveFlag: true, hasPromptSources: false))
    #expect(!ChatInteractiveLoop.shouldRun(interactiveFlag: true, hasPromptSources: true))
}

@Test func chatInteractiveLoopParsesSystemCommands() {
    #expect(ChatInteractiveLoop.systemPromptPath(from: "/system ./prompt.txt") == "./prompt.txt")
    #expect(ChatInteractiveLoop.systemPromptPath(from: "/system reset") == nil)
    #expect(ChatInteractiveLoop.isSystemResetCommand("/system reset"))
    #expect(!ChatInteractiveLoop.isSystemResetCommand("/system ./prompt.txt"))
}

@Test func chatInteractiveLoopLoadsSystemPromptFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("system.txt")
    try "Custom Ultramar system".write(to: fileURL, atomically: true, encoding: .utf8)

    let loaded = try ChatInteractiveLoop.loadSystemPrompt(path: fileURL.path)
    #expect(loaded == "Custom Ultramar system")
}
