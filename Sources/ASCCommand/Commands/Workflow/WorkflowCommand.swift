import ArgumentParser
import Domain
import Foundation

struct WorkflowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "Run multi-step automation workflows",
        subcommands: [WorkflowRunCommand.self, WorkflowValidateCommand.self, WorkflowListCommand.self]
    )
}

struct WorkflowRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a named workflow"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Preview execution without side effects")
    var dryRun: Bool = false

    @Option(name: .long, help: "Path to workflow file")
    var file: String = ".asc/workflow.json"

    @Argument(help: "Workflow name")
    var name: String

    @Argument(help: "Optional runtime params in KEY:VALUE form")
    var params: [String] = []

    func run() throws {
        print(try execute())
    }

    func execute(
        loader: (String) throws -> WorkflowDefinition = loadWorkflowDefinition,
        runner: (String, [String: String]) throws -> WorkflowRunStepResult = defaultShellRunner,
        environmentProvider: () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) throws -> String {
        let definition = try loader(file)
        let issues = validateWorkflowDefinition(definition)
        guard issues.isEmpty else {
            throw ValidationError("Invalid workflow file. Run `asc workflow validate --file \(file)` first.")
        }

        guard let rootWorkflow = definition.workflows[name] else {
            throw ValidationError("Workflow '\(name)' not found in \(file)")
        }

        let runtime = try parseRuntimeParams(params)
        let baseEnv = definition.env.merging(environmentProvider()) { _, new in new }
        let rootEnv = baseEnv.merging(rootWorkflow.env) { _, new in new }.merging(runtime) { _, new in new }

        var beforeAllResult: WorkflowRunStepResult?
        var afterAllResult: WorkflowRunStepResult?
        var errorHookResult: WorkflowRunStepResult?
        var stepResults: [WorkflowRunStepResult] = []
        var outputStore: [String: [String: String]] = [:]

        if !definition.beforeAll.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if dryRun {
                beforeAllResult = WorkflowRunStepResult(step: "before_all", command: definition.beforeAll, success: true, exitCode: 0, output: "dry-run")
            } else {
                beforeAllResult = try runner(definition.beforeAll, rootEnv)
                if beforeAllResult?.success == false {
                    let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
                    return try formatter.format(WorkflowRunEnvelope(
                        command: "workflow run",
                        file: file,
                        name: name,
                        dryRun: false,
                        status: "failed_before_all",
                        beforeAll: beforeAllResult,
                        steps: [],
                        afterAll: nil,
                        errorHook: nil
                    ))
                }
            }
        }

        let succeeded = try executeWorkflowSteps(
            definition: definition,
            workflowName: name,
            workflow: rootWorkflow,
            inheritedEnv: rootEnv,
            dryRun: dryRun,
            runner: runner,
            outputStore: &outputStore,
            stepResults: &stepResults
        )

        if !succeeded, !definition.errorHook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if dryRun {
                errorHookResult = WorkflowRunStepResult(step: "error", command: definition.errorHook, success: true, exitCode: 0, output: "dry-run")
            } else {
                errorHookResult = try runner(definition.errorHook, rootEnv)
            }
        }

        if succeeded, !definition.afterAll.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if dryRun {
                afterAllResult = WorkflowRunStepResult(step: "after_all", command: definition.afterAll, success: true, exitCode: 0, output: "dry-run")
            } else {
                afterAllResult = try runner(definition.afterAll, rootEnv)
            }
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(WorkflowRunEnvelope(
            command: "workflow run",
            file: file,
            name: name,
            dryRun: dryRun,
            status: dryRun ? "dry_run" : (succeeded ? "completed" : "failed"),
            beforeAll: beforeAllResult,
            steps: stepResults,
            afterAll: afterAllResult,
            errorHook: errorHookResult
        ))
    }
}

struct WorkflowValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate workflow.json for errors and cycles"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to workflow file")
    var file: String = ".asc/workflow.json"

    func run() throws {
        print(try execute())
    }

    func execute(loader: (String) throws -> WorkflowDefinition = loadWorkflowDefinition) throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        do {
            let definition = try loader(file)
            let issues = validateWorkflowDefinition(definition)
            return try formatter.format(WorkflowValidateEnvelope(
                command: "workflow validate",
                file: file,
                valid: issues.isEmpty,
                errors: issues
            ))
        } catch {
            return try formatter.format(WorkflowValidateEnvelope(
                command: "workflow validate",
                file: file,
                valid: false,
                errors: ["Failed to load workflow file: \(error.localizedDescription)"]
            ))
        }
    }
}

struct WorkflowListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available workflows"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Include private workflows")
    var all: Bool = false

    @Option(name: .long, help: "Path to workflow file")
    var file: String = ".asc/workflow.json"

    func run() throws {
        print(try execute())
    }

    func execute(loader: (String) throws -> WorkflowDefinition = loadWorkflowDefinition) throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        do {
            let definition = try loader(file)
            let items = definition.workflows.keys.sorted().compactMap { key -> WorkflowListItem? in
                guard let wf = definition.workflows[key] else { return nil }
                if !all, wf.isPrivate { return nil }
                return WorkflowListItem(name: key, description: wf.description, isPrivate: wf.isPrivate)
            }

            return try formatter.format(WorkflowListEnvelope(
                command: "workflow list",
                file: file,
                includePrivate: all,
                workflows: items
            ))
        } catch {
            return try formatter.format(WorkflowListEnvelope(
                command: "workflow list",
                file: file,
                includePrivate: all,
                workflows: []
            ))
        }
    }
}

struct WorkflowDefinition: Codable {
    let env: [String: String]
    let beforeAll: String
    let afterAll: String
    let errorHook: String
    let workflows: [String: WorkflowSpec]

    enum CodingKeys: String, CodingKey {
        case env
        case beforeAll = "before_all"
        case afterAll = "after_all"
        case errorHook = "error"
        case workflows
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        beforeAll = try container.decodeIfPresent(String.self, forKey: .beforeAll) ?? ""
        afterAll = try container.decodeIfPresent(String.self, forKey: .afterAll) ?? ""
        errorHook = try container.decodeIfPresent(String.self, forKey: .errorHook) ?? ""
        workflows = try container.decode([String: WorkflowSpec].self, forKey: .workflows)
    }
}

struct WorkflowSpec: Codable {
    let description: String?
    let isPrivate: Bool
    let env: [String: String]
    let steps: [WorkflowStep]

    enum CodingKeys: String, CodingKey {
        case description
        case isPrivate = "private"
        case env
        case steps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        steps = try container.decodeIfPresent([WorkflowStep].self, forKey: .steps) ?? []
    }
}

struct WorkflowStep: Codable {
    let run: String?
    let workflow: String?
    let name: String?
    let condition: String?
    let with: [String: String]
    let outputs: [String: String]

    enum CodingKeys: String, CodingKey {
        case run
        case workflow
        case name
        case condition = "if"
        case with
        case outputs
    }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let run = try? single.decode(String.self) {
            self.run = run
            workflow = nil
            name = nil
            condition = nil
            with = [:]
            outputs = [:]
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        run = try container.decodeIfPresent(String.self, forKey: .run)
        workflow = try container.decodeIfPresent(String.self, forKey: .workflow)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        with = try container.decodeIfPresent([String: String].self, forKey: .with) ?? [:]
        outputs = try container.decodeIfPresent([String: String].self, forKey: .outputs) ?? [:]
    }
}

struct WorkflowRunStepResult: Encodable {
    let step: String
    let command: String
    let success: Bool
    let exitCode: Int32
    let output: String?
}

private struct WorkflowRunEnvelope: Encodable {
    let command: String
    let file: String
    let name: String
    let dryRun: Bool
    let status: String
    let beforeAll: WorkflowRunStepResult?
    let steps: [WorkflowRunStepResult]
    let afterAll: WorkflowRunStepResult?
    let errorHook: WorkflowRunStepResult?
}

private struct WorkflowValidateEnvelope: Encodable {
    let command: String
    let file: String
    let valid: Bool
    let errors: [String]
}

private struct WorkflowListItem: Encodable {
    let name: String
    let description: String?
    let isPrivate: Bool
}

private struct WorkflowListEnvelope: Encodable {
    let command: String
    let file: String
    let includePrivate: Bool
    let workflows: [WorkflowListItem]
}

private func loadWorkflowDefinition(path: String) throws -> WorkflowDefinition {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(WorkflowDefinition.self, from: data)
}

private func parseRuntimeParams(_ params: [String]) throws -> [String: String] {
    var result: [String: String] = [:]
    for item in params {
        let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            throw ValidationError("Invalid runtime param '\(item)'. Expected KEY:VALUE")
        }
        result[parts[0]] = parts[1]
    }
    return result
}

private func validateWorkflowDefinition(_ definition: WorkflowDefinition) -> [String] {
    var issues: [String] = []

    if definition.workflows.isEmpty {
        issues.append("workflow file must define at least one workflow")
        return issues
    }

    for (name, wf) in definition.workflows.sorted(by: { $0.key < $1.key }) {
        if wf.steps.isEmpty {
            issues.append("workflow '\(name)' must have at least one step")
            continue
        }
        for (index, step) in wf.steps.enumerated() {
            let idx = index + 1
            let hasRun = !(step.run?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasWorkflow = !(step.workflow?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if !hasRun && !hasWorkflow {
                issues.append("workflow '\(name)' step \(idx) must have run or workflow")
            }
            if hasRun && hasWorkflow {
                issues.append("workflow '\(name)' step \(idx) cannot contain both run and workflow")
            }
            if hasRun, !step.with.isEmpty {
                issues.append("workflow '\(name)' step \(idx) cannot use with on run step")
            }
            if hasWorkflow, let ref = step.workflow?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty,
               definition.workflows[ref] == nil {
                issues.append("workflow '\(name)' step \(idx) references unknown workflow '\(ref)'")
            }
            if !step.outputs.isEmpty {
                if hasWorkflow {
                    issues.append("workflow '\(name)' step \(idx) cannot use outputs on workflow step")
                }
                let trimmedName = step.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmedName.isEmpty {
                    issues.append("workflow '\(name)' step \(idx) must provide name when using outputs")
                }
                for (outputName, outputExpr) in step.outputs.sorted(by: { $0.key < $1.key }) {
                    if !isValidOutputIdentifier(outputName) {
                        issues.append("workflow '\(name)' step \(idx) has invalid output name '\(outputName)'")
                    }
                    if !isValidOutputExpression(outputExpr) {
                        issues.append("workflow '\(name)' step \(idx) output '\(outputName)' must be JSON path like $.field")
                    }
                }
            }
        }
    }

    if let cycle = detectWorkflowCycle(definition) {
        issues.append("cyclic workflow reference: \(cycle)")
    }

    return issues
}

private func detectWorkflowCycle(_ definition: WorkflowDefinition) -> String? {
    enum Color { case white, gray, black }
    var colors = Dictionary(uniqueKeysWithValues: definition.workflows.keys.map { ($0, Color.white) })
    var stack: [String] = []

    func dfs(_ name: String) -> String? {
        colors[name] = .gray
        stack.append(name)

        guard let wf = definition.workflows[name] else {
            _ = stack.popLast()
            colors[name] = .black
            return nil
        }

        for step in wf.steps {
            guard let ref = step.workflow?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { continue }
            if colors[ref] == .gray {
                if let start = stack.firstIndex(of: ref) {
                    return (stack[start...] + [ref]).joined(separator: " -> ")
                }
                return "\(name) -> \(ref)"
            }
            if colors[ref] == .white, let found = dfs(ref) {
                return found
            }
        }

        _ = stack.popLast()
        colors[name] = .black
        return nil
    }

    for name in definition.workflows.keys.sorted() {
        if colors[name] == .white, let found = dfs(name) {
            return found
        }
    }

    return nil
}

private func isValidOutputIdentifier(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first, first.isLetter else { return false }
    return trimmed.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
}

private func isValidOutputExpression(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("$.") else { return false }
    let parts = trimmed.dropFirst(2).split(separator: ".")
    guard !parts.isEmpty else { return false }
    return parts.allSatisfy { part in
        guard let first = part.first, first.isLetter else { return false }
        return part.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

private func executeWorkflowSteps(
    definition: WorkflowDefinition,
    workflowName: String,
    workflow: WorkflowSpec,
    inheritedEnv: [String: String],
    dryRun: Bool,
    runner: (String, [String: String]) throws -> WorkflowRunStepResult,
    outputStore: inout [String: [String: String]],
    stepResults: inout [WorkflowRunStepResult]
) throws -> Bool {
    for (index, step) in workflow.steps.enumerated() {
        let idx = index + 1
        let stepLabel = "\(workflowName)#\(idx)"

        if let conditionKey = step.condition?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conditionKey.isEmpty,
           !isTruthy(inheritedEnv[conditionKey] ?? ProcessInfo.processInfo.environment[conditionKey] ?? "") {
            stepResults.append(
                WorkflowRunStepResult(
                    step: stepLabel,
                    command: step.run ?? "",
                    success: true,
                    exitCode: 0,
                    output: "skipped"
                )
            )
            continue
        }

        if let ref = step.workflow?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            guard let child = definition.workflows[ref] else {
                stepResults.append(
                    WorkflowRunStepResult(
                        step: stepLabel,
                        command: "workflow:\(ref)",
                        success: false,
                        exitCode: 1,
                        output: "unknown workflow"
                    )
                )
                return false
            }

            let resolvedWith = try resolveWithValues(step.with, outputStore: outputStore)
            let childEnv = inheritedEnv
                .merging(child.env) { _, new in new }
                .merging(resolvedWith) { _, new in new }

            let ok = try executeWorkflowSteps(
                definition: definition,
                workflowName: ref,
                workflow: child,
                inheritedEnv: childEnv,
                dryRun: dryRun,
                runner: runner,
                outputStore: &outputStore,
                stepResults: &stepResults
            )
            if !ok { return false }
            continue
        }

        guard let runCommand = step.run?.trimmingCharacters(in: .whitespacesAndNewlines), !runCommand.isEmpty else {
            stepResults.append(
                WorkflowRunStepResult(step: stepLabel, command: "", success: false, exitCode: 1, output: "missing action")
            )
            return false
        }

        let resolvedCommand = try interpolateStepOutputReferences(runCommand, outputStore: outputStore, shellEscape: true)

        if dryRun {
            stepResults.append(
                WorkflowRunStepResult(step: stepLabel, command: resolvedCommand, success: true, exitCode: 0, output: "dry-run")
            )
            continue
        }

        let result = try runner(resolvedCommand, inheritedEnv)
        let mappedResult = WorkflowRunStepResult(
            step: stepLabel,
            command: resolvedCommand,
            success: result.success,
            exitCode: result.exitCode,
            output: result.output
        )
        stepResults.append(mappedResult)

        if !result.success {
            return false
        }

        if !step.outputs.isEmpty {
            do {
                let extracted = try extractStepOutputs(from: result.output, declarations: step.outputs)
                if let producerName = step.name?.trimmingCharacters(in: .whitespacesAndNewlines), !producerName.isEmpty {
                    outputStore[producerName] = extracted
                }
            } catch {
                stepResults.append(
                    WorkflowRunStepResult(
                        step: stepLabel,
                        command: resolvedCommand,
                        success: false,
                        exitCode: 1,
                        output: "output extraction failed: \(error.localizedDescription)"
                    )
                )
                return false
            }
        }
    }

    return true
}

private func resolveWithValues(_ values: [String: String], outputStore: [String: [String: String]]) throws -> [String: String] {
    guard !values.isEmpty else { return [:] }
    var resolved: [String: String] = [:]
    for key in values.keys.sorted() {
        resolved[key] = try interpolateStepOutputReferences(values[key] ?? "", outputStore: outputStore, shellEscape: false)
    }
    return resolved
}

private func isTruthy(_ value: String) -> Bool {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "y", "on":
        return true
    default:
        return false
    }
}

private func interpolateStepOutputReferences(
    _ input: String,
    outputStore: [String: [String: String]],
    shellEscape: Bool
) throws -> String {
    let regex = try NSRegularExpression(pattern: #"\$\{steps\.([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_]+)\}"#)
    let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
    let matches = regex.matches(in: input, range: nsRange)

    var result = input
    for match in matches.reversed() {
        guard
            match.numberOfRanges == 3,
            let tokenRange = Range(match.range(at: 0), in: result),
            let stepRange = Range(match.range(at: 1), in: result),
            let outputRange = Range(match.range(at: 2), in: result)
        else {
            continue
        }

        let token = String(result[tokenRange])
        let stepName = String(result[stepRange])
        let outputName = String(result[outputRange])

        guard let value = outputStore[stepName]?[outputName] else {
            throw ValidationError("Unknown step output reference: \(token)")
        }

        let replacement = shellEscape ? shellQuoted(value) : value
        result.replaceSubrange(tokenRange, with: replacement)
    }

    return result
}

private func shellQuoted(_ value: String) -> String {
    if value.isEmpty { return "''" }
    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private func extractStepOutputs(from output: String?, declarations: [String: String]) throws -> [String: String] {
    guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationError("step output is empty")
    }

    let data = Data(output.utf8)
    let json = try JSONSerialization.jsonObject(with: data)

    var extracted: [String: String] = [:]
    for key in declarations.keys.sorted() {
        let path = declarations[key] ?? ""
        extracted[key] = try evaluateJSONPath(json: json, expression: path)
    }
    return extracted
}

private func evaluateJSONPath(json: Any, expression: String) throws -> String {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("$.") else {
        throw ValidationError("Unsupported JSON path: \(expression)")
    }

    var current: Any = json
    for segment in trimmed.dropFirst(2).split(separator: ".") {
        guard let object = current as? [String: Any], let next = object[String(segment)] else {
            throw ValidationError("JSON path missing field: \(segment)")
        }
        current = next
    }

    switch current {
    case let value as String:
        return value
    case let value as NSNumber:
        return value.stringValue
    case is NSNull:
        throw ValidationError("JSON path resolved to null")
    default:
        let encoded = try JSONSerialization.data(withJSONObject: current)
        return String(data: encoded, encoding: .utf8) ?? ""
    }
}

private func defaultShellRunner(command: String, environment: [String: String]) throws -> WorkflowRunStepResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.environment = environment

    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    try process.run()
    process.waitUntilExit()

    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    let merged = (String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")

    return WorkflowRunStepResult(
        step: "shell",
        command: command,
        success: process.terminationStatus == 0,
        exitCode: process.terminationStatus,
        output: merged.isEmpty ? nil : merged
    )
}
