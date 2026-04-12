import ArgumentParser

struct MetadataCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metadata",
        abstract: "File-backed metadata workflows",
        subcommands: [MetadataPull.self, MetadataPush.self, MetadataValidate.self]
    )
}
