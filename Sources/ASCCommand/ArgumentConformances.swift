import ArgumentParser
import Domain

extension AppStorePlatform: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(cliArgument: argument)
    }
}
