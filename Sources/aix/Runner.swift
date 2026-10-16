import AixCore
import Foundation

/// Checks and runs a plan's commands as one script in the user's shell.
struct Runner {
    let shell: String

    /// Joins commands into one script so `cd` and variables carry over, stopping at the first failure.
    func script(_ commands: [String]) -> String {
        "set -e\n" + commands.joined(separator: "\n")
    }

    /// Problems found without running anything: syntax errors and programs that aren't installed.
    func issues(in commands: [String]) -> [String] {
        var found: [String] = []
        let syntax = capture([shell, "-n", "-c", script(commands)])
        if syntax.status != 0 {
            let msg = syntax.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            found.append("syntax error: \(msg.isEmpty ? "exit \(syntax.status)" : msg)")
        }
        let programs = Array(Set(commands.flatMap(Shell.programs(in:)))).sorted()
        if !programs.isEmpty {
            let probe = capture([shell, "-c", #"for c; do command -v "$c" >/dev/null 2>&1 || echo "$c"; done"#, "aix"] + programs)
            for name in probe.stdout.split(separator: "\n") {
                found.append("`\(name)`: command not found (not installed on this Mac)")
            }
        }
        return found
    }

    /// Runs the plan attached to the terminal. stderr is shown live and also kept for a retry.
    func run(_ commands: [String]) -> (status: Int32, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-c", script(commands)]
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

    private func capture(_ argv: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (127, "", "could not start \(argv[0])") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}

private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.withLock { data.append(d) } }
    var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
