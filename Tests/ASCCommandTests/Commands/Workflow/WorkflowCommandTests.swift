import Foundation
import Testing
@testable import ASCCommand

@Suite
struct WorkflowCommandTests {
    @Test func `workflow list returns public workflows by default`() throws {
        let cmd = try WorkflowListCommand.parse([])
        let output = try cmd.execute(loader: { _ in
            try JSONDecoder().decode(WorkflowDefinition.self, from: Data(definitionJSON.utf8))
        })

        #expect(output.contains("\"name\":\"beta\""))
        #expect(!output.contains("\"name\":\"private_flow\""))
    }

    @Test func `workflow validate detects cycle`() throws {
        let cmd = try WorkflowValidateCommand.parse([])
        let output = try cmd.execute(loader: { _ in
            try JSONDecoder().decode(WorkflowDefinition.self, from: Data(cycleDefinitionJSON.utf8))
        })

        #expect(output.contains("\"valid\":false"))
        #expect(output.contains("cyclic workflow reference"))
    }

    @Test func `workflow run dry-run returns planned steps`() throws {
        let cmd = try WorkflowRunCommand.parse(["--dry-run", "beta", "BUILD:123"])
        let output = try cmd.execute(
            loader: { _ in
                try JSONDecoder().decode(WorkflowDefinition.self, from: Data(definitionJSON.utf8))
            },
            runner: { _, _ in
                WorkflowRunStepResult(step: "ignored", command: "", success: true, exitCode: 0, output: nil)
            },
            environmentProvider: { [:] }
        )

        #expect(output.contains("\"status\":\"dry_run\""))
        #expect(output.contains("echo beta"))
    }

    @Test func `workflow run executes and reports failure`() throws {
        let cmd = try WorkflowRunCommand.parse(["beta"])
        var called = 0
        let output = try cmd.execute(
            loader: { _ in
                try JSONDecoder().decode(WorkflowDefinition.self, from: Data(definitionJSON.utf8))
            },
            runner: { command, _ in
                called += 1
                if command == "echo beta" {
                    return WorkflowRunStepResult(step: "shell", command: command, success: false, exitCode: 1, output: "boom")
                }
                return WorkflowRunStepResult(step: "shell", command: command, success: true, exitCode: 0, output: nil)
            },
            environmentProvider: { [:] }
        )

        #expect(called >= 1)
        #expect(output.contains("\"status\":\"failed\""))
        #expect(output.contains("boom"))
    }

    @Test func `workflow run skips step when if condition is falsy`() throws {
        let cmd = try WorkflowRunCommand.parse(["beta"])
        var calledCommands: [String] = []

        _ = try cmd.execute(
            loader: { _ in
                try JSONDecoder().decode(WorkflowDefinition.self, from: Data(conditionDefinitionJSON.utf8))
            },
            runner: { command, _ in
                calledCommands.append(command)
                return WorkflowRunStepResult(step: "shell", command: command, success: true, exitCode: 0, output: nil)
            },
            environmentProvider: { [:] }
        )

        #expect(calledCommands == ["echo always"])
    }

    @Test func `workflow run resolves outputs into later command and with env`() throws {
        let cmd = try WorkflowRunCommand.parse(["beta"])
        var calls: [(command: String, env: [String: String])] = []

        _ = try cmd.execute(
            loader: { _ in
                try JSONDecoder().decode(WorkflowDefinition.self, from: Data(outputsDefinitionJSON.utf8))
            },
            runner: { command, env in
                calls.append((command, env))
                if command == "echo source" {
                    return WorkflowRunStepResult(
                        step: "shell",
                        command: command,
                        success: true,
                        exitCode: 0,
                        output: "{\"token\":\"abc123\"}"
                    )
                }
                return WorkflowRunStepResult(step: "shell", command: command, success: true, exitCode: 0, output: nil)
            },
            environmentProvider: { [:] }
        )

        #expect(calls.count == 3)
        #expect(calls[1].command.contains("abc123"))
        #expect(calls[2].env["FROM_WITH"] == "abc123")
    }
}


private let definitionJSON = #"""
{
  "workflows": {
    "beta": {
      "description": "Beta flow",
      "steps": [
        { "run": "echo beta" },
        { "workflow": "private_flow" }
      ]
    },
    "private_flow": {
      "private": true,
      "steps": [
        { "run": "echo private" }
      ]
    }
  }
}
"""#

private let cycleDefinitionJSON = #"""
{
  "workflows": {
    "a": { "steps": [ { "workflow": "b" } ] },
    "b": { "steps": [ { "workflow": "a" } ] }
  }
}
"""#

private let conditionDefinitionJSON = #"""
{
  "workflows": {
    "beta": {
      "env": { "RUN_ME": "false" },
      "steps": [
        { "if": "RUN_ME", "run": "echo conditional" },
        { "run": "echo always" }
      ]
    }
  }
}
"""#

private let outputsDefinitionJSON = #"""
{
  "workflows": {
    "beta": {
      "steps": [
        {
          "name": "resolve",
          "run": "echo source",
          "outputs": { "TOKEN": "$.token" }
        },
        {
          "run": "echo ${steps.resolve.TOKEN}"
        },
        {
          "workflow": "child",
          "with": {
            "FROM_WITH": "${steps.resolve.TOKEN}"
          }
        }
      ]
    },
    "child": {
      "steps": [
        { "run": "echo child" }
      ]
    }
  }
}
"""#
