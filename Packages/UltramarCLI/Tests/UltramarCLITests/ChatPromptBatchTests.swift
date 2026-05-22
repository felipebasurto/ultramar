import Foundation
import Testing
@testable import ultramar

@Test func chatPromptBatchMergesRepeatedFlags() throws {
    let prompts = try ChatPromptBatch.resolve(
        commandPrompts: ["first", "second"],
        promptsFile: nil,
        useStdin: false,
        useStdinLines: false,
        stdinData: Data()
    )
    #expect(prompts == ["first", "second"])
}

@Test func chatPromptBatchParsesFileAndSkipsComments() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("prompts.txt")
    try """
    # travel smoke
    Tips for Bangkok offline

    ¿Agua del grifo en Tailandia?
    """.write(to: fileURL, atomically: true, encoding: .utf8)

    let prompts = try ChatPromptBatch.resolve(
        commandPrompts: ["hello"],
        promptsFile: fileURL.path,
        useStdin: false,
        useStdinLines: false,
        stdinData: Data()
    )
    #expect(prompts.count == 3)
    #expect(prompts[0] == "hello")
    #expect(prompts[1] == "Tips for Bangkok offline")
    #expect(prompts[2] == "¿Agua del grifo en Tailandia?")
}

@Test func chatPromptBatchStdinLinesReadsOnePromptPerLine() throws {
    let stdin = """
    line one
    line two
    """
    let prompts = try ChatPromptBatch.resolve(
        commandPrompts: [],
        promptsFile: nil,
        useStdin: false,
        useStdinLines: true,
        stdinData: Data(stdin.utf8)
    )
    #expect(prompts == ["line one", "line two"])
}

@Test func chatPromptBatchStdinPreservesMultilinePrompt() throws {
    let stdin = """
    one paragraph
    with a newline
    """
    let prompts = try ChatPromptBatch.resolve(
        commandPrompts: [],
        promptsFile: nil,
        useStdin: true,
        useStdinLines: false,
        stdinData: Data(stdin.utf8)
    )
    #expect(prompts.count == 1)
    #expect(prompts[0].contains("one paragraph"))
    #expect(prompts[0].contains("with a newline"))
}
