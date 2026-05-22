import Foundation

enum ChatPromptBatch {
    enum Error: Swift.Error, LocalizedError {
        case missingInput
        case promptsFileNotFound(String)
        case promptsFileEmpty(String)
        case stdinEmpty

        var errorDescription: String? {
            switch self {
            case .missingInput:
                "No prompts specified."
            case .promptsFileNotFound(let path):
                "Prompts file not found: \(path)"
            case .promptsFileEmpty(let path):
                "Prompts file has no non-empty lines: \(path)"
            case .stdinEmpty:
                "Empty stdin."
            }
        }
    }

    static func resolve(
        commandPrompts: [String],
        promptsFile: String?,
        useStdin: Bool,
        useStdinLines: Bool,
        stdinData: Data,
        fileManager: FileManager = .default
    ) throws -> [String] {
        var collected: [String] = []

        for prompt in commandPrompts {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                collected.append(trimmed)
            }
        }

        if let promptsFile {
            let path = (promptsFile as NSString).expandingTildeInPath
            guard fileManager.fileExists(atPath: path) else {
                throw Error.promptsFileNotFound(path)
            }
            let url = URL(fileURLWithPath: path)
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = parseLines(content)
            guard !lines.isEmpty else {
                throw Error.promptsFileEmpty(path)
            }
            collected.append(contentsOf: lines)
        }

        if useStdin || useStdinLines {
            guard let text = String(data: stdinData, encoding: .utf8) else {
                throw Error.stdinEmpty
            }
            if useStdinLines {
                let lines = parseLines(text)
                guard !lines.isEmpty else {
                    throw Error.stdinEmpty
                }
                collected.append(contentsOf: lines)
            } else {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw Error.stdinEmpty
                }
                collected.append(trimmed)
            }
        }

        guard !collected.isEmpty else {
            throw Error.missingInput
        }
        return collected
    }

    static func parseLines(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
