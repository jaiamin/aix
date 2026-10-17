import AixCore
import Foundation

/// Checks and runs a command in the user's shell.
struct Runner {
    let shell: String

    /// Problems found without running anything: syntax errors and programs that aren't installed.
    func issues(in script: String) -> [String] {
        guard !script.isEmpty else { return [] }
        var found: [String] = []
        let syntax = capture([shell, "-n", "-c", script])
        if syntax.status != 0 {
            let msg = syntax.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            found.append("syntax error: \(msg.isEmpty ? "exit \(syntax.status)" : msg)")
        }
        let programs = Array(Set(Shell.programs(in: script))).sorted()
        if !programs.isEmpty {
            let probe = capture([shell, "-c", #"for c; do command -v "$c" >/dev/null 2>&1 || echo "$c"; done"#, "aix"] + programs)
            for name in probe.stdout.split(separator: "\n") {
                found.append("`\(name)`: command not found (not installed on this Mac)")
            }
        }
        return found
    }

    /// Runs the script attached to the terminal. stderr is shown live and also kept for a retry.
    func run(_ script: String) -> (status: Int32, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-c", script]
        let errPipe = Pipe()
        p.standardError = errPipe
        let buffer = Buffer()
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
            buffer.append(data)
        }
        do {
            try p.run()
        } catch {
            return (127, "could not start \(shell): \(error.localizedDescription)")
        }
        p.waitUntilExit()
        errPipe.fileHandleForReading.readabilityHandler = nil
        buffer.append(errPipe.fileHandleForReading.readDataToEndOfFile())
        return (p.terminationStatus, buffer.string)
    }
}

private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.withLock { data.append(d) } }
    var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
