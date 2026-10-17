import AixCore
import Foundation
import FoundationModels

let version = "0.2.2"
let maxRepairs = 2  // automatic retries when a plan has syntax errors or missing programs

func fail(_ message: String, code: Int32 = 1) -> Never {
    Terminal.err("aix: \(message)\n")
    exit(code)
}

func describe(_ error: Error) -> String {
    switch error as? LanguageModelSession.GenerationError {
    case .guardrailViolation: "Apple's safety filter blocked this request. Try rewording it."
    case .refusal: "The model declined this request."
    case .exceededContextWindowSize: "That was too long for the on-device model. Try a shorter request or a smaller folder."
    default: "\(error)"
    }
}

/// One blank line separates blocks; none trails the output, so the shell prompt keeps its own spacing.
func show(_ plan: Plan) {
    print()
    if let explanation = plan.explanation, !explanation.isEmpty {
        print("  " + explanation)
        guard !plan.commands.isEmpty else { return }
        print()
    } else if plan.commands.isEmpty {
        print("  aix couldn't turn that into a command. Try rewording it.")
        return
    }
    for command in plan.commands {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false)
        print("  " + Terminal.cyan("$") + " " + Terminal.bold(String(lines[0])))
        for line in lines.dropFirst() { print("    " + Terminal.bold(String(line))) }
    }
    print()
}

/// Lines to show before running: why it's blocked, what it changes, and known problems.
func warnings(blocked: String?, risks: [String], issues: [String]) -> [String] {
    var lines = blocked.map { ["✗ Blocked: this \($0). aix won't run it."] } ?? []
    if !risks.isEmpty { lines.append("⚠ This " + risks.joined(separator: ", ") + ".") }
    return lines + issues.map { "⚠ " + $0 }
}

/// Asks the model, then lets it repair syntax errors or missing programs.
@MainActor
func generate(_ message: String, label: String, planner: Planner, runner: Runner) async throws -> (plan: Plan, issues: [String]) {
    var plan = try await Spinner.run(label) { try await planner.plan(message) }
    var issues = runner.issues(in: plan.script)
    for _ in 0..<maxRepairs where !issues.isEmpty {
        let repair = Prompt.repair(issues: issues)
        plan = try await Spinner.run("Fixing") { try await planner.plan(repair) }
        issues = runner.issues(in: plan.script)
    }
    return (plan, issues)
}

Terminal.installInterruptHandler()

let opts: Options
do {
    opts = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error). Run aix -h for help.", code: 2)
}
if opts.version { print("aix \(version)"); exit(0) }
if opts.help { print(Options.usage); exit(0) }
if case .initShell(let shell) = opts.mode {
    guard shell == "zsh" else { fail("only zsh is supported for now") }
    print(ShellIntegration.zsh)
    exit(0)
}

let env = ProcessInfo.processInfo.environment
let interactive = isatty(STDIN_FILENO) != 0 && !opts.print
var request = opts.prompt  // what gets saved to history; empty for fix and explain
var message = ""
switch opts.mode {
case .run:
    if request.isEmpty {
        guard interactive else { print(Options.usage); exit(2) }
        guard let line = Terminal.ask(Terminal.cyan("aix › ")), !line.isEmpty else { exit(0) }
        request = line
    }
    message = Prompt.request(request)
case .fix:
    guard let command = env["AIX_LAST_COMMAND"]?.trimmingCharacters(in: .whitespaces), !command.isEmpty,
          let status = env["AIX_LAST_STATUS"].flatMap(Int32.init) else {
        fail("shell integration is needed for fix. Add this to ~/.zshrc:\n  eval \"$(aix init zsh)\"")
    }
    guard status != 0 else {
        print("Your last command worked: \(command)")
        exit(0)
    }
    message = Prompt.fix(command: command, status: status)
case .explain(let command):
    message = Prompt.explain(command)
case .initShell:
    break
}

@MainActor
func makePlanner(_ instructions: String) -> Planner {
    debug(instructions)
    do {
        return try Planner(instructions: instructions)
    } catch {
        fail(describe(error))
    }
}

if case .explain = opts.mode {
    do {
        let planner = makePlanner(Prompt.explainInstructions)
        let text = try await Spinner.run("Explaining") { try await planner.explain(message) }
        print()
        for line in text.split(separator: "\n") { print("  " + line) }
        exit(0)
    } catch {
        fail(describe(error))
    }
}

let shell = Environment.runnableShell(from: env["SHELL"])
let environment = Environment.current(shell: shell)
let runner = Runner(shell: shell)
let history = History.standard(env: env)
let planner = makePlanner(Prompt.instructions(for: environment, request: request, personal: history.load()))

var label = opts.mode == .fix ? "Fixing" : "Generating"

while true {
    let plan: Plan, issues: [String]
    do {
        (plan, issues) = try await generate(message, label: label, planner: planner, runner: runner)
    } catch {
        fail(describe(error))
    }
    let blocked = Safety.violation(in: plan.script, home: environment.home)
    let notes = warnings(blocked: blocked, risks: Safety.risks(in: plan.script), issues: issues)

    // Shell integration: the command goes to stdout for the prompt line, notes to stderr.
    if opts.print {
        Terminal.err(([plan.explanation ?? ""] + notes).filter { !$0.isEmpty }.joined(separator: "\n"))
        guard blocked == nil, !plan.commands.isEmpty else { exit(1) }
        print(plan.commands.joined(separator: " && "))
        exit(0)
    }

    show(plan)
    if plan.commands.isEmpty { exit(0) }  // an answer, or a refusal with its reason
    for note in notes { Terminal.err((blocked != nil && note == notes[0] ? Terminal.red(note) : Terminal.yellow(note)) + "\n") }
    if blocked != nil { exit(1) }
    if opts.dryRun { exit(0) }

    // -y skips the question, but never for a plan that still has known problems.
    if !opts.yes || !issues.isEmpty {
        guard interactive else { fail("no terminal to confirm on; pass -y to run without asking") }
        switch Terminal.choose("Run?", hint: "y/N · r refine · c copy", keys: "yrc") {
        case "y":
            break
        case "r":
            guard let change = Terminal.ask(Terminal.cyan("Refine › ")), !change.isEmpty else { exit(0) }
            message = Prompt.refine(change)
            label = "Refining"
            continue
        case "c":
            let copied = capture(["/usr/bin/pbcopy"], input: plan.commands.joined(separator: "\n")).status == 0
            Terminal.err(Terminal.dim(copied ? "Copied to clipboard." : "Couldn't copy.") + "\n")
            exit(copied ? 0 : 1)
        default:
            Terminal.err(Terminal.dim("Cancelled.") + "\n")
            exit(0)
        }
    }

    let result = runner.run(plan.script)
    if result.status == 0 {
        if !request.isEmpty { history.record(.init(request: request, commands: plan.commands)) }
        exit(0)
    }

    Terminal.err(Terminal.red("✗ Exited with status \(result.status)") + "\n")
    guard interactive, Terminal.choose("Ask aix to fix it?", hint: "y/N", keys: "y") == "y" else {
        exit(result.status)
    }
    message = Prompt.failure(status: result.status, stderr: result.stderr)
    label = "Fixing"
}
