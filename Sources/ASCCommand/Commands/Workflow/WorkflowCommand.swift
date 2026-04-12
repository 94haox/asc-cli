import ArgumentParser
import Domain
import Foundation

struct WorkflowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "Manage file-based workflow definitions",
        subcommands: [
            WorkflowList.self,
            WorkflowValidate.self,
            WorkflowRun.self,
        ],
        defaultSubcommand: WorkflowList.self
    )
}

struct WorkflowList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List workflows from a workflow definition file"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Workflow file path")
    var file: String = ".asc/workflow.json"

    @Flag(name: .long, help: "Include private workflows")
    var all: Bool = false

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let config = try WorkflowFileSupport.load(file: file, fileManager: fileManager)
        let items = config.workflows
            .sorted { $0.key < $1.key }
            .filter { all || !$0.value.isPrivate }
            .map { name, workflow in
                WorkflowListItem(name: name, isPrivate: workflow.isPrivate, stepsCount: workflow.steps.count)
            }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(items)
    }
}

struct WorkflowValidate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a workflow definition file and placeholder syntax"
    )

    @Option(name: .long, help: "Workflow file path")
    var file: String = ".asc/workflow.json"

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        do {
            let config = try WorkflowFileSupport.load(file: file, fileManager: fileManager)
            let errors = WorkflowFileSupport.validate(config: config)
            let result = WorkflowValidationResult(valid: errors.isEmpty, errors: errors, workflows: Array(config.workflows.keys).sorted())
            let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
            return try formatter.format(result)
        } catch {
            let result = WorkflowValidationResult(valid: false, errors: [error.localizedDescription], workflows: [])
            let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
            return try formatter.format(result)
        }
    }
}

struct WorkflowRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Preview a workflow plan from file with validated substitutions"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Workflow file path")
    var file: String = ".asc/workflow.json"

    @Flag(name: .long, help: "Only preview the workflow plan without executing it")
    var dryRun: Bool = false

    @Argument(help: "Workflow name")
    var workflowName: String

    @Argument(help: "Parameter substitutions in key:value form; malformed tokens are rejected")
    var parameters: [String] = []

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let config = try WorkflowFileSupport.load(file: file, fileManager: fileManager)
        try WorkflowFileSupport.validateOrThrow(config: config)
        let substitutions = try WorkflowFileSupport.parseSubstitutions(parameters)
        guard let workflow = config.workflows[workflowName] else {
            throw ValidationError("Workflow '\(workflowName)' was not found in \(file).")
        }

        let planned = workflow.steps.enumerated().map { index, step in
            WorkflowRunStep(
                name: step.displayName(index: index),
                command: WorkflowFileSupport.render(step: step, substitutions: substitutions)
            )
        }

        let result = WorkflowRunResult(
            status: dryRun ? "dry-run" : "planned",
            stepsExecuted: planned.count,
            failedStep: nil,
            planned: planned
        )
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(result)
    }
}

private struct WorkflowListItem: Codable, AffordanceProviding, Presentable {
    let name: String
    let isPrivate: Bool
    let stepsCount: Int

    static let tableHeaders = ["Name", "Private", "Steps"]

    var tableRow: [String] {
        [name, isPrivate ? "true" : "false", "\(stepsCount)"]
    }

    var affordances: [String: String] {
        [
            "run": "asc workflow run \(name)",
            "validate": "asc workflow validate",
        ]
    }
}

private struct WorkflowValidationResult: Codable {
    let valid: Bool
    let errors: [String]
    let workflows: [String]
}

private struct WorkflowRunResult: Codable {
    let status: String
    let stepsExecuted: Int
    let failedStep: String?
    let planned: [WorkflowRunStep]
}

private struct WorkflowRunStep: Codable {
    let name: String
    let command: String
}

private enum WorkflowFileSupport {
    static func load(file: String, fileManager: FileManager) throws -> WorkflowConfig {
        let url = URL(fileURLWithPath: file)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ValidationError("Workflow file not found at \(file).")
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        let normalized = normalize(raw)
        let data = Data(normalized.utf8)
        return try JSONDecoder().decode(WorkflowConfig.self, from: data)
    }

    static func validate(config: WorkflowConfig) -> [String] {
        var errors: [String] = []
        if config.workflows.isEmpty {
            errors.append("workflows must not be empty")
        }

        for (name, workflow) in config.workflows {
            if workflow.steps.isEmpty {
                errors.append("workflow '\(name)' must include at least one step")
            }
            for step in workflow.steps {
                if let error = validate(step: step, workflowName: name) {
                    errors.append(error)
                }
            }
        }

        return errors
    }

    static func validateOrThrow(config: WorkflowConfig) throws {
        let errors = validate(config: config)
        guard errors.isEmpty else {
            throw ValidationError("Workflow file validation failed: \(errors.joined(separator: "; "))")
        }
    }

    static func parseSubstitutions(_ parameters: [String]) throws -> [String: String] {
        var substitutions: [String: String] = [:]

        for parameter in parameters {
            let parts = parameter.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw ValidationError("Workflow run parameter '\(parameter)' must use key:value form.")
            }
            substitutions[String(parts[0])] = String(parts[1])
        }

        return substitutions
    }

    static func render(step: WorkflowStep, substitutions: [String: String]) -> String {
        let command = step.command
        return substitutions.reduce(command) { partialResult, entry in
            partialResult.replacingOccurrences(of: "X:\(entry.key)", with: entry.value)
        }
    }

    private static func validate(step: WorkflowStep, workflowName: String) -> String? {
        if step.command.isEmpty {
            return "workflow '\(workflowName)' step '\(step.name ?? "<unnamed>")' must include a run command"
        }
        if let placeholderError = validatePlaceholderSyntax(step.command, workflowName: workflowName, stepName: step.name ?? "<unnamed>") {
            return placeholderError
        }
        return nil
    }

    private static func validatePlaceholderSyntax(_ command: String, workflowName: String, stepName: String) -> String? {
        var searchStart = command.startIndex

        while let range = command.range(of: "X:", range: searchStart..<command.endIndex) {
            let placeholderStart = range.upperBound
            guard placeholderStart < command.endIndex else {
                return "workflow '\(workflowName)' step '\(stepName)' contains malformed placeholder syntax near 'X:'."
            }

            let placeholderEnd = command[placeholderStart...].firstIndex(where: { $0.isWhitespace }) ?? command.endIndex
            let placeholder = String(command[placeholderStart..<placeholderEnd])

            guard !placeholder.isEmpty, !placeholder.contains(":") else {
                return "workflow '\(workflowName)' step '\(stepName)' contains malformed placeholder syntax near 'X:\(placeholder)'."
            }

            searchStart = placeholderEnd
        }

        return nil
    }

    private static func normalize(_ raw: String) -> String {
        let withoutComments = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let string = String(line)
                if let range = string.range(of: "//") {
                    return String(string[..<range.lowerBound])
                }
                return string
            }
            .joined(separator: "\n")

        let pattern = #",\s*([}\]])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return withoutComments
        }
        let range = NSRange(withoutComments.startIndex..<withoutComments.endIndex, in: withoutComments)
        return regex.stringByReplacingMatches(
            in: withoutComments,
            options: [],
            range: range,
            withTemplate: "$1"
        )
    }
}

private struct WorkflowConfig: Codable {
    let workflows: [String: WorkflowDefinition]
}

private struct WorkflowDefinition: Codable {
    let isPrivate: Bool
    let steps: [WorkflowStep]

    init(isPrivate: Bool = false, steps: [WorkflowStep]) {
        self.isPrivate = isPrivate
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey {
        case isPrivate = "private"
        case steps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        steps = try container.decode([WorkflowStep].self, forKey: .steps)
    }
}

private struct WorkflowStep: Codable {
    let name: String?
    let command: String

    init(name: String?, command: String) {
        self.name = name
        self.command = command
    }

    init(from decoder: any Decoder) throws {
        if let string = try? String(from: decoder) {
            name = nil
            command = string
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        command = try container.decodeIfPresent(String.self, forKey: .run)
            ?? container.decodeIfPresent(String.self, forKey: .command)
            ?? ""
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(command, forKey: .run)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case run
        case command
    }
}

private extension WorkflowStep {
    func displayName(index: Int) -> String {
        name ?? "step-\(index + 1)"
    }
}
