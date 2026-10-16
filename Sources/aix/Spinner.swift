import AixCore
import Foundation

/// The one-line 3×3 cube loader (see `Cube`) with a label and elapsed time, drawn on stderr.
enum Spinner {
    static let interval = Duration.milliseconds(80)

    static func run<T>(_ label: String, _ work: () async throws -> T) async throws -> T {
        guard isatty(STDERR_FILENO) != 0 else { return try await work() }
        Terminal.hideCursor()
        let animation = Task.detached {
            var frame = 0
            let start = ContinuousClock.now
            while !Task.isCancelled {
                draw(frame: frame, label: label, elapsed: ContinuousClock.now - start)
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

    static func draw(frame: Int, label: String, elapsed: Duration) {
        let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        Terminal.err("\r\u{1b}[2K\u{1b}[36m\(Cube.frame(frame))\u{1b}[0m \(label) \u{1b}[2m\(String(format: "%.1fs", secs))\u{1b}[0m")
    }

    static func clear() {
        Terminal.err("\r\u{1b}[2K")
    }
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
}
