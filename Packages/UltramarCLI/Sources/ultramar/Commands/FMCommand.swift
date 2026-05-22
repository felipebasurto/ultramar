import ArgumentParser
import UltramarLLM

struct FM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fm",
        abstract: "Apple Foundation Models gate status.",
        subcommands: [Status.self],
        defaultSubcommand: Status.self
    )
}

extension FM {
    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show FMGateDetector snapshot.",
            usage: """
            Examples:
              ultramar fm status
              ultramar fm status --format json
            """
        )

        @OptionGroup var global: GlobalOptions

        func run() {
            let gate = FMGateDetector.current()
            CLIOutput.print(
                [
                    "ok": .bool(true),
                    "available": .bool(gate.isAvailable),
                    "os_version_ok": .bool(gate.osVersionOK),
                    "device_supported": .bool(gate.deviceSupported),
                    "apple_intelligence_enabled": .bool(gate.appleIntelligenceEnabled),
                    "locale_supported": .bool(gate.localeSupported),
                    "user_toggle_on": .bool(gate.userToggleOn),
                ],
                format: global.format
            )
        }
    }
}
