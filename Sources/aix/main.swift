import AixCore
import Foundation
import FoundationModels

let version = "0.1.0"
let maxRepairs = 2  // automatic re-asks when a plan has syntax errors or missing programs
let maxFixes = 2    // re-asks the user can approve after a command fails

func fail(_ message: String, code: Int32 = 1) -> Never {
    Terminal.err("aix: \(message)\n")
    exit(code)
}

func confirm(_ question: String) -> Bool {
    Terminal.err("\(question) \(Terminal.dim("[y/N]")) ")
    guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
    return answer == "y" || answer == "yes"
}

func describe(_ error: Error) -> String {
    if let e = error as? LanguageModelSession.GenerationError {
        switch e {
        case .guardrailViolation: return "Apple's safety filter blocked this request."
        case .refusal: return "The model declined this request."
        case .exceededContextWindowSize: return "The request and folder listing were too long for the model."
        default: break
        }
    }
    return "\(error)"
}

func show(_ plan: Plan) {
    print()
    print("  " + plan.explanation)
    print()
    for command in plan.commands {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false)
        print("  " + Terminal.cyan("$") + " " + Terminal.bold(String(lines[0])))
        for line in lines.dropFirst() { print("    " + Terminal.bold(String(line))) }
    }
    print()
}

Terminal.installInterruptHandler()

let opts: Options
do {
    opts = try Options.parse(Array(CommandLine.arguments.dropFirst()), env: ProcessInfo.processInfo.environment)
} catch {
    fail("\(error)\n\n\(Options.usage)", code: 2)
}
if opts.version { print("aix \(version)"); exit(0) }
if opts.help { print(Options.usage); exit(0) }

let shell = Environment.runnableShell(from: ProcessInfo.processInfo.environment["SHELL"])
let environment = Environment.current(shell: shell)
let runner = Runner(shell: shell)
let interactive = isatty(STDIN_FILENO) != 0

let planner: Planner
do {
    planner = try Planner(choice: opts.model, instructions: Prompt.instructions(for: environment))
} catch {
    fail(describe(error))
}

var request = opts.prompt
var fixesLeft = maxFixes

while true {
    var plan: Plan
    var issues: [String] = []
    do {
        plan = try await Spinner.run("Generating") { try await planner.plan(request) }
        issues = plan.commands.isEmpty ? [] : runner.issues(in: plan.commands)
        var repairs = 0
        while !issues.isEmpty && repairs < maxRepairs {
            repairs += 1
            let prompt = Prompt.repair(issues: issues)
            plan = try await Spinner.run("Fixing") { try await planner.plan(prompt) }
            issues = plan.commands.isEmpty ? [] : runner.issues(in: plan.commands)
        }
    } catch {
        fail(describe(error))
    }

    show(plan)
    if plan.commands.isEmpty { exit(1) }

    if let reason = plan.commands.lazy.compactMap({ Safety.violation(in: $0, home: environment.home) }).first {
        Terminal.err(Terminal.red("✗ Blocked: this \(reason). aix won't run it.") + "\n")
        exit(1)
    }
    for issue in issues { Terminal.err(Terminal.yellow("⚠ \(issue)") + "\n") }
    if opts.dryRun { exit(0) }

    // Never auto-run a plan that still has known problems.
    if !opts.yes || !issues.isEmpty {
        guard interactive else { fail("no terminal to confirm on; pass -y to run without asking") }
        guard confirm("Run?") else {
            Terminal.err(Terminal.dim("Cancelled.") + "\n")
            exit(0)
        }
    }

    let result = runner.run(plan.commands)
    if result.status == 0 { exit(0) }

    Terminal.err(Terminal.red("✗ Exited with status \(result.status)") + "\n")
    guard fixesLeft > 0, interactive, confirm("Ask aix to fix it?") else { exit(result.status) }
    fixesLeft -= 1
    request = Prompt.failure(status: result.status, stderr: result.stderr)
}
