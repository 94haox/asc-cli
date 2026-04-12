import ArgumentParser

struct SigningCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "signing",
        abstract: "Manage workspace-backed signing snapshots",
        subcommands: [
            SigningSyncCommand.self,
        ]
    )
}

struct SigningSyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync local signing snapshots",
        subcommands: [
            SigningSyncPull.self,
            SigningSyncPush.self,
        ]
    )
}
