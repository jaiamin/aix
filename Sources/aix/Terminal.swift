import AixCore
import Foundation

/// A cycling ■ ● ▲ glyph with a highlight sweeping across the label, drawn on one line of stderr.
enum Spinner {
    static let interval = Duration.milliseconds(90)
    // 256-color greys for the label: resting → fully lit.
    static let dimGrey = 244
    static let brightGrey = 255

    static func run<T>(_ label: String, _ work: () async throws -> T) async throws -> T {
        guard isatty(STDERR_FILENO) != 0 else { return try await work() }
        Terminal.hideCursor()
        let animation = Task.detached {
            var frame = 0
            while !Task.isCancelled {
                draw(frame: frame, label: label + "...")
                frame += 1
                try? await Task.sleep(for: interval)
            }
        }
        defer { Terminal.showCursor() }
        do {
            let value = try await work()
            animation.cancel()
            await animation.value
            clear()
            return value
        } catch {
            animation.cancel()
            await animation.value
            clear()
            throw error
        }
    }

    static func draw(frame: Int, label: String) {
        let levels = Animation.shimmer(count: label.count, frame: frame)
        var text = ""
        for (char, level) in zip(label, levels) {
            let grey = dimGrey + Int((Double(brightGrey - dimGrey) * level).rounded())
            text += "\u{1b}[38;5;\(grey)m\(char)"
        }
        Terminal.err("\r\u{1b}[2K\u{1b}[36m\(Animation.glyph(frame))\u{1b}[0m \(text)\u{1b}[0m")
    }

    static func clear() {
        Terminal.err("\r\u{1b}[2K")
    }
}

/// Prints to stderr when AIX_DEBUG is set (prompt, model errors).
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
    static func green(_ s: String) -> String { style(s, "32") }
    static func yellow(_ s: String) -> String { style(s, "33") }
    static func cyan(_ s: String) -> String { style(s, "36") }

    /// Restores the cursor if the user hits Ctrl-C while it is hidden.
    static func installInterruptHandler() {
        signal(SIGINT) { _ in
            let reset = "\u{1b}[?25h\n"
            reset.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            _exit(130)
        }
    }

    /// Reads a line of text after `prompt`. Nil on end of input.
    static func ask(_ prompt: String) -> String? {
        err(prompt)
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Asks a question answered by one keypress, no Enter. Returns the key if it is one of
    /// `keys` (lowercased), otherwise "n".
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

    /// Reads one byte from the terminal without waiting for Enter or echoing it.
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
