import AixCore
import Foundation
import FoundationModels

let version = "0.1.0"
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

let interactive = isatty(STDIN_FILENO) != 0
var request = opts.prompt
if request.isEmpty {
    guard interactive else { print(Options.usage); exit(2) }
    guard let line = Terminal.ask(Terminal.cyan("aix › ")), !line.isEmpty else { exit(0) }
    request = line
}

let shell = Environment.runnableShell(from: ProcessInfo.processInfo.environment["SHELL"])
let environment = Environment.current(shell: shell)
let runner = Runner(shell: shell)

let instructions = Prompt.instructions(for: environment, request: request)
debug(instructions)

let planner: Planner
do {
    planner = try Planner(instructions: instructions)
} catch {
    fail(describe(error))
}

var message = Prompt.request(request)
var label = "Generating"

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

    show(plan)
    if plan.commands.isEmpty { exit(1) }

    if let reason = Safety.violation(in: plan.script, home: environment.home) {
        Terminal.err(Terminal.red("✗ Blocked: this \(reason). aix won't run it.") + "\n")
        exit(1)
    }
    for issue in issues { Terminal.err(Terminal.yellow("⚠ \(issue)") + "\n") }
    let risks = Safety.risks(in: plan.script)
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
    if result.status == 0 { exit(0) }

    Terminal.err(Terminal.red("✗ Exited with status \(result.status)") + "\n")
    guard interactive, Terminal.choose("Ask aix to fix it?", hint: "y/N", keys: "y") == "y" else {
        exit(result.status)
    }
    message = Prompt.failure(status: result.status, stderr: result.stderr)
    label = "Fixing"
}
