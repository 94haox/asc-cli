import ArgumentParser

struct MigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "File-backed migration workflows",
        subcommands: [MigrateExport.self, MigrateValidate.self, MigrateImport.self]
    )
}
