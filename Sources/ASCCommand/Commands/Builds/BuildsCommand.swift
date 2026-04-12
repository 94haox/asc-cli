import ArgumentParser

struct BuildsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "builds",
        abstract: "Manage builds",
        subcommands: [
            BuildsList.self,
            BuildsInfo.self,
            BuildsNextNumber.self,
            BuildsNextBuildNumber.self,
            BuildsUpload.self,
            BuildsArchive.self,
            BuildsUploadsCommand.self,
            BuildsAddBetaGroup.self,
            BuildsRemoveBetaGroup.self,
            BuildsAddGroups.self,
            BuildsRemoveGroups.self,
            BuildsUpdateBetaNotes.self,
            BuildsTestNotesCommand.self,
        ]
    )
}
