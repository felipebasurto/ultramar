import ArgumentParser

enum ChatBackendOption: String, ExpressibleByArgument, CaseIterable, Sendable {
    case server
    case embedded
}
