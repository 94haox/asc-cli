import ArgumentParser

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "Manage apps",
        subcommands: [AppsList.self, AppsView.self, AppsWallCommand.self]
    )
}
