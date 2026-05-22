import ArgumentParser
import Foundation
import UltramarLLM

struct Models: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List, inspect, download, and remove on-device GGUF models.",
        subcommands: [List.self, Status.self, Download.self, Remove.self],
        defaultSubcommand: Status.self
    )
}

extension Models {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Show model catalog entries.",
            usage: """
            Examples:
              ultramar models list
              ultramar models list --format json
            """
        )

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let entries = [
                catalogEntry(ModelCatalog.qwenBrain),
                catalogEntry(ModelCatalog.gemmaVision),
            ]

            switch global.format {
            case .text:
                for entry in entries {
                    for (key, value) in entry.sorted(by: { $0.key < $1.key }) {
                        Swift.print("\(key): \(value.textRepresentation)")
                    }
                    Swift.print("---")
                }
            case .json:
                CLIOutput.print(["models": .array(entries.map { .object($0) })], format: .json)
            }
        }

        private func catalogEntry(_ artifact: ModelArtifact) -> [String: JSONValue] {
            [
                "id": .string(artifact.id),
                "engine": .string(artifact.role.rawValue),
                "display_name": .string(artifact.displayName),
                "filename": .string(artifact.filename),
                "expected_bytes": .int64(artifact.expectedBytes),
                "url": .string(ModelCatalog.resolveURL(for: artifact).absoluteString),
                "sha256_pinned": .bool(artifact.sha256 != nil),
            ]
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show install state from manifest.json.",
            usage: """
            Examples:
              ultramar models status
              ultramar models status --engine qwen --format json
              ultramar models status --engine all
            """
        )

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Engine: qwen, gemma, or all.")
        var engine: EngineOption = .all

        func run() async throws {
            let (qwen, gemma) = await CLIModelFacade.refreshStatus()
            let canonical = try CLIPaths.canonicalModelsDirectory().path

            switch engine {
            case .qwen:
                printState(id: "qwen", state: qwen, artifact: ModelCatalog.qwenBrain)
            case .gemma:
                printState(id: "gemma", state: gemma, artifact: ModelCatalog.gemmaVision)
            case .all:
                printState(id: "qwen", state: qwen, artifact: ModelCatalog.qwenBrain)
                if global.format == .text { Swift.print("---") }
                printState(id: "gemma", state: gemma, artifact: ModelCatalog.gemmaVision)
            }

            if global.format == .text {
                Swift.print("manifest_dir: \(canonical)")
            }
        }

        private func printState(id: String, state: ModelInstallState, artifact: ModelArtifact) {
            let path = ModelCatalog.localURL(for: artifact).path
            CLIOutput.print(
                [
                    "engine": .string(id),
                    "artifact_id": .string(artifact.id),
                    "state": .string(state.logLabel),
                    "installed": .bool(state.isInstalled),
                    "path": .string(path),
                    "on_disk": .bool(FileManager.default.fileExists(atPath: path)),
                ],
                format: global.format
            )
        }
    }

    struct Download: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "download",
            abstract: "Download a GGUF model (Wi‑Fi by default).",
            usage: """
            Examples:
              ultramar models download --engine qwen
              ultramar models download --engine gemma --cellular
              ultramar models download --engine qwen --dry-run
            """
        )

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Engine to download: qwen or gemma.")
        var engine: EngineOption

        @Flag(name: .long, help: "Allow download over cellular data.")
        var cellular: Bool = false

        @Flag(name: .long, help: "Show what would download without starting.")
        var dryRun: Bool = false

        func validate() throws {
            guard engine == .qwen || engine == .gemma else {
                throw ValidationError("Missing or invalid --engine. Use qwen or gemma.")
            }
        }

        func run() async throws {
            do {
                let result = try await CLIModelFacade.download(
                    engine: engine,
                    allowsCellular: cellular,
                    dryRun: dryRun
                )
                CLIOutput.print(
                    [
                        "ok": .bool(true),
                        "artifact": .string(result.artifactID),
                        "path": .string(result.path),
                        "bytes": .int64(result.bytesOnDisk),
                        "already_installed": .bool(result.alreadyInstalled),
                        "dry_run": .bool(result.dryRun),
                    ],
                    format: global.format
                )
            } catch let error as CLIError {
                CLIOutput.printError(error.localizedDescription, hint: error.hint, format: global.format)
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove an installed model.",
            usage: """
            Examples:
              ultramar models remove --engine qwen --yes
              ultramar models remove --engine qwen --dry-run --yes
            """
        )

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Engine to remove: qwen or gemma.")
        var engine: EngineOption

        @Flag(name: .long, help: "Skip confirmation (required).")
        var yes: Bool = false

        @Flag(name: .long, help: "Show what would be removed without deleting.")
        var dryRun: Bool = false

        func validate() throws {
            guard engine == .qwen || engine == .gemma else {
                throw ValidationError("Missing or invalid --engine. Use qwen or gemma.")
            }
        }

        func run() async throws {
            do {
                try await CLIModelFacade.remove(engine: engine, yes: yes, dryRun: dryRun)
                CLIOutput.print(
                    [
                        "ok": .bool(true),
                        "engine": .string(engine.rawValue),
                        "removed": .bool(!dryRun),
                        "dry_run": .bool(dryRun),
                    ],
                    format: global.format
                )
            } catch let error as CLIError {
                CLIOutput.printError(error.localizedDescription, hint: error.hint, format: global.format)
            }
        }
    }
}
