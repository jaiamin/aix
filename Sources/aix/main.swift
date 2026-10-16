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

/// Asks a yes/no question answered by a single keypress: y runs, anything else (Enter too) declines.
func confirm(_ question: String) -> Bool {
    Terminal.err("\(question) \(Terminal.dim("[y/N]")) ")
    let key = readKey()
    if key == 3 {  // Ctrl-C (signals are off while reading the key)
        Terminal.err("\n")
        exit(130)
    }
    let yes = key == UInt8(ascii: "y") || key == UInt8(ascii: "Y")
    Terminal.err((yes ? "y" : "n") + "\n")
    return yes
}

/// Reads one byte from the terminal without waiting for Enter or echoing it.
func readKey() -> UInt8? {
    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
        return readLine()?.utf8.first
    }
    var raw = original
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
    withUnsafeMutableBytes(of: &raw.c_cc) { cc in
        cc[Int(VMIN)] = 1
        cc[Int(VTIME)] = 0
    }
    // TCSAFLUSH drops keys typed during generation, so an early "y" can't approve an unseen plan.
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    defer { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
    var byte: UInt8 = 0
    return read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
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

/// One blank line separates blocks; none trails the output, so the shell prompt follows
/// with its own spacing.
func show(_ plan: Plan) {
    print()
    print("  " + plan.explanation)
    guard !plan.commands.isEmpty else { return }
    print()
    for command in plan.commands {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false)
        print("  " + Terminal.cyan("$") + " " + Terminal.bold(String(lines[0])))
        for line in lines.dropFirst() { print("    " + Terminal.bold(String(line))) }
    }
    print()  // before "Run?" or a warning
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
