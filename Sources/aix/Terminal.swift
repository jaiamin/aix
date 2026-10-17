import AixCore
import Foundation

/// Shows "■ Generating..." until the plan starts arriving, then the plan itself, redrawn as it
/// grows. Drawn on stderr and cleared at the end, so the final output prints normally.
final class Live: @unchecked Sendable {
    private let label: String
    private let enabled = isatty(STDERR_FILENO) != 0
    private let lock = NSLock()
    private var rows = 0
    private var spinning = true
    private var animation: Task<Void, Never>?

    init(_ label: String) { self.label = label + "..." }

    func start() {
        guard enabled else { return }
        Terminal.hideCursor()
        animation = Task.detached { [self] in
            var frame = 0
            while !Task.isCancelled {
                lock.withLock { if spinning { replace(with: [Self.spinner(label, frame: frame)]) } }
                frame += 1
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    /// Shows the plan so far; the spinner stays until there's something to show.
    func show(_ lines: [String]) {
        guard enabled, lines.contains(where: { !$0.isEmpty }) else { return }
        lock.withLock {
            spinning = false
            replace(with: lines)
        }
    }

    /// Back to the spinner, when a retry starts over.
    func reset() {
        guard enabled else { return }
        lock.withLock { spinning = true }
    }

    func finish() {
        guard enabled else { return }
        animation?.cancel()
        lock.withLock {
            spinning = false
            replace(with: [])
        }
        Terminal.showCursor()
    }

    /// Erases what was drawn and draws `lines`, counting rows that wrap. Call with the lock held.
    private func replace(with lines: [String]) {
        var out = rows > 0 ? "\u{1b}[\(rows)A" : ""
        out += "\r\u{1b}[J"
        var size = winsize()
        let columns = ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0 ? Int(size.ws_col) : 80
        rows = 0
        for line in lines {
            out += line + "\n"
            let width = line.replacing(/\u{1b}\[[0-9;?]*[A-Za-z]/, with: "").count
            rows += max(1, (width + columns - 1) / columns)
        }
        FileHandle.standardError.write(Data(out.utf8))
    }

    static func spinner(_ label: String, frame: Int) -> String {
        let levels = Animation.shimmer(count: label.count, frame: frame)
        var text = ""
        for (char, level) in zip(label, levels) {
            text += "\u{1b}[38;5;\(244 + Int((11 * level).rounded()))m\(char)"
        }
        return "\u{1b}[36m\(Animation.glyph(frame))\u{1b}[0m \(text)\u{1b}[0m"
    }
}

/// AIX_DEBUG=1 prints the prompt and model errors.
func debug(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["AIX_DEBUG"] != nil else { return }
    Terminal.err(Terminal.dim("[debug] " + message()) + "\n")
}

enum Terminal {
    static let isColor = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func err(_ s: String) {
        fflush(stdout)  // keep stdout (the plan) and stderr (prompts, warnings) in order
        FileHandle.standardError.write(Data(s.utf8))
    }
    static func hideCursor() { err("\u{1b}[?25l") }
    static func showCursor() { err("\u{1b}[?25h") }

    static func style(_ s: String, _ code: String) -> String {
        isColor ? "\u{1b}[\(code)m\(s)\u{1b}[0m" : s
    }
    static func dim(_ s: String) -> String { style(s, "2") }

    static func bold(_ s: String) -> String { style(s, "1") }
    static func red(_ s: String) -> String { style(s, "31") }
    static func yellow(_ s: String) -> String { style(s, "33") }
    static func cyan(_ s: String) -> String { style(s, "36") }

    /// The plan as printed: a blank line, the explanation, a blank line, then the commands.
    /// Shared by the live view and the final output so they look identical.
    static func planLines(explanation: String?, commands: [String]) -> [String] {
        var lines = [""]
        if let explanation, !explanation.isEmpty {
            lines.append("  " + explanation)
            if !commands.isEmpty { lines.append("") }
        }
        for command in commands where !command.isEmpty {
            let parts = command.split(separator: "\n", omittingEmptySubsequences: false)
            lines.append("  " + cyan("$") + " " + bold(String(parts[0])))
            lines += parts.dropFirst().map { "    " + bold(String($0)) }
        }
        if !commands.isEmpty { lines.append("") }
        return lines
    }

    /// Prints a plan. One blank line separates blocks; none trails, so the shell prompt keeps its spacing.
    static func show(_ plan: Plan) {
        guard plan.explanation?.isEmpty == false || !plan.commands.isEmpty else {
            print("\n  aix couldn't turn that into a command. Try rewording it.")
            return
        }
        for line in planLines(explanation: plan.explanation, commands: plan.commands) { print(line) }
    }

    /// Lines to show before running: why it's blocked, what it changes, and known problems.
    static func warnings(blocked: String?, risks: [String], issues: [String]) -> [String] {
        var lines = blocked.map { ["✗ Blocked: this \($0). aix won't run it."] } ?? []
        if !risks.isEmpty { lines.append("⚠ This " + risks.joined(separator: ", ") + ".") }
        return lines + issues.map { "⚠ " + $0 }
    }

    /// Restores the cursor on Ctrl-C.
    static func installInterruptHandler() {
        signal(SIGINT) { _ in
            let reset = "\u{1b}[?25h\n"
            reset.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            _exit(130)
        }
    }

    static func ask(_ prompt: String) -> String? {
        err(prompt)
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One keypress, no Enter. Returns the key if it's in `keys`, otherwise "n".
    static func choose(_ question: String, hint: String, keys: String) -> Character {
        err("\(question) \(dim(hint)) ")
        let byte = readKey()
        if byte == 3 {  // Ctrl-C; signals are off while reading the key
            err("\n")
            exit(130)
        }
        let key = byte.map { Character(UnicodeScalar($0)).lowercased().first! } ?? "n"
        let choice = keys.contains(key) ? key : "n"
        err("\(choice)\n")
        return choice
    }

    private static func readKey() -> UInt8? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return readLine()?.utf8.first }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        // TCSAFLUSH drops keys typed while generating, so an early "y" can't approve an unseen plan.
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        defer { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
        var byte: UInt8 = 0
        return read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
    }
}
