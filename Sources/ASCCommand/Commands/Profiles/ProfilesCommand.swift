import ArgumentParser

struct ProfilesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profiles",
        abstract: "Manage provisioning profiles",
        subcommands: [
            ProfilesList.self,
            ProfilesCreate.self,
            ProfilesDelete.self,
            ProfilesDownload.self,
        ]
    )
}
