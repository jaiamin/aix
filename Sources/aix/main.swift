import AixCore
import Foundation
import FoundationModels

let version = "0.2.0"
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

func copyToClipboard(_ text: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    let pipe = Pipe()
    p.standardInput = pipe
    guard (try? p.run()) != nil else { return false }
    pipe.fileHandleForWriting.write(Data(text.utf8))
    try? pipe.fileHandleForWriting.close()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

Terminal.installInterruptHandler()

let opts: Options
do {
    opts = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)\n\n\(Options.usage)", code: 2)
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
        fail("aix fix needs shell integration. Add this to ~/.zshrc:\n  eval \"$(aix init zsh)\"")
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

let shell = Environment.runnableShell(from: env["SHELL"])
let environment = Environment.current(shell: shell)
let runner = Runner(shell: shell)
let history = History.standard(env: env)

let instructions: String
if case .explain = opts.mode {
    instructions = Prompt.explainInstructions
} else {
    instructions = Prompt.instructions(for: environment, request: request, personal: history.load())
}
debug(instructions)

let planner: Planner
do {
    planner = try Planner(instructions: instructions)
} catch {
    fail(describe(error))
}

if case .explain = opts.mode {
    do {
        let text = try await Spinner.run("Explaining") { try await planner.explain(message) }
        print()
        for line in text.split(separator: "\n") { print("  " + line) }
        exit(0)
    } catch {
        fail(describe(error))
    }
}

var label = opts.mode == .fix ? "Fixing" : "Generating"

while true {
    var plan: Plan
    var issues: [String] = []
    do {
        let first = message
        plan = try await Spinner.run(label) { try await planner.plan(first) }
        issues = runner.issues(in: plan.script)
        var repairs = 0
        while !issues.isEmpty && repairs < maxRepairs {
            repairs += 1
            let repair = Prompt.repair(issues: issues)
            plan = try await Spinner.run("Fixing") { try await planner.plan(repair) }
            issues = runner.issues(in: plan.script)
        }
    } catch {
        fail(describe(error))
    }

    let blocked = Safety.violation(in: plan.script, home: environment.home)
    let risks = Safety.risks(in: plan.script)

    // Shell integration: the command goes to stdout for the prompt line, notes to stderr.
    if opts.print {
        var notes = [plan.explanation ?? ""]
        if let blocked { notes = ["✗ Blocked: this \(blocked)."] }
        if !risks.isEmpty { notes.append("⚠ This " + risks.joined(separator: ", ") + ".") }
        notes += issues.map { "⚠ " + $0 }
        Terminal.err(notes.filter { !$0.isEmpty }.joined(separator: "\n"))
        guard blocked == nil, !plan.commands.isEmpty else { exit(1) }
        print(plan.commands.joined(separator: " && "))
        exit(0)
    }

    show(plan)
    if plan.commands.isEmpty { exit(0) }  // an answer, or a refusal with its reason

    if let blocked {
        Terminal.err(Terminal.red("✗ Blocked: this \(blocked). aix won't run it.") + "\n")
        exit(1)
    }
    for issue in issues { Terminal.err(Terminal.yellow("⚠ \(issue)") + "\n") }
    if !risks.isEmpty { Terminal.err(Terminal.yellow("⚠ This " + risks.joined(separator: ", ") + ".") + "\n") }
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
            let copied = copyToClipboard(plan.commands.joined(separator: "\n"))
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
