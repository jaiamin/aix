import Foundation

/// Facts about the user's machine that the model can't know on its own.
public struct Environment: Sendable {
    public var osVersion: String
    public var shell: String
    public var cwd: String
    public var home: String
    public var entries: [String]

    public init(osVersion: String, shell: String, cwd: String, home: String, entries: [String]) {
        self.osVersion = osVersion
        self.shell = shell
        self.cwd = cwd
        self.home = home
        self.entries = entries
    }

    /// Shells that understand `-c`, `-n` and `set -e` the same way. Anything else (fish, nu…) runs zsh.
    public static func runnableShell(from env: String?) -> String {
        guard let env, ["zsh", "bash", "sh", "ksh", "dash"].contains((env as NSString).lastPathComponent) else { return "/bin/zsh" }
        return env
    }

    public static func current(shell: String) -> Environment {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let names = ((try? fm.contentsOfDirectory(atPath: cwd)) ?? []).sorted()
        let entries = names.map { name -> String in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: (cwd as NSString).appendingPathComponent(name), isDirectory: &isDir)
            return isDir.boolValue ? name + "/" : name
        }
        return Environment(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            shell: shell,
            cwd: cwd,
            home: fm.homeDirectoryForCurrentUser.path,
            entries: entries
        )
    }
}

public enum Prompt {
    static let maxEntries = 60

    public static func instructions(for env: Environment) -> String {
        let shown = env.entries.prefix(maxEntries).joined(separator: "  ")
        let more = env.entries.count > maxEntries ? "  … and \(env.entries.count - maxEntries) more" : ""
        let parent = (env.cwd as NSString).deletingLastPathComponent
        return """
        You turn a user's request into shell commands that will run in their terminal.

        ENVIRONMENT
        - OS: macOS \(env.osVersion). The tools are BSD versions, not GNU/Linux.
        - Shell: \((env.shell as NSString).lastPathComponent), run non-interactively with errexit.
        - Current folder (".", "here"): \(env.cwd)
        - Parent folder (".."): \(parent)
        - Home folder ("~"): \(env.home)
        - Current folder contains (\(env.entries.count) entries, "/" marks folders): \(shown.isEmpty ? "(empty)" : shown)\(more)

        HOW TO ANSWER
        - Return the commands in the order they should run. They run in one shell, so `cd` carries over.
        - Do exactly what was asked: if the user wants a count, a total or the top N, produce that number or list, not raw data.
        - Resolve folders the user names ("parent folder", "Downloads", "here") to the paths above. Search subfolders with `find` unless told otherwise.
        - Use only options that exist in macOS's BSD tools. GNU/Linux-only options (`--max-depth`, `find -printf`, `stat -c`, `xargs -d`) fail here.
        - Prefer one clear pipeline over several steps. Quote paths that may contain spaces.
        - Never use sudo. Only delete, move or overwrite files when the user explicitly asks, and target the narrowest path.
        - The commands run on the real Mac with network access and the usual tools (git, curl, lsof, find, zip…). You don't need to know what files exist: write commands that find out.
        - Return no commands only if the request would destroy data or the system, or isn't a computer task at all. Then say why in the explanation.

        EXAMPLES (from other folders; adapt the paths to the environment above)
        \(examples)
        """
    }

    /// Worked macOS examples. A small model copies patterns far more reliably than it follows rules.
    static let examples = [
        ("3 biggest log files under /var/log", ["find /var/log -type f -name '*.log' -exec du -k {} + 2>/dev/null | sort -rn | head -3"]),
        ("how many lines of python are in src", ["find src -type f -name '*.py' -exec cat {} + | wc -l"]),
        ("pdfs in Documents changed this week, newest first", ["find ~/Documents -type f -name '*.pdf' -mtime -7 -exec ls -lt {} +"]),
        ("what's listening on port 3000", ["lsof -nP -iTCP:3000 -sTCP:LISTEN"]),
        ("rename every .jpeg here to .jpg", [#"for f in *.jpeg; do mv -- "$f" "${f%.jpeg}.jpg"; done"#]),
        ("make a notes folder with an empty todo.txt in it", ["mkdir -p notes", "touch notes/todo.txt"]),
        ("size of each folder in the parent folder", ["du -sh ../*/ | sort -rh"]),
        ("wipe my disk", [String]()),
    ].map { request, commands in
        let list = commands.isEmpty
            ? "  (none; the explanation says why)"
            : commands.map { "  " + $0 }.joined(separator: "\n")
        return "Request: \(request)\nCommands:\n\(list)"
    }.joined(separator: "\n\n")

    public static func repair(issues: [String]) -> String {
        """
        Those commands won't work on this Mac:
        \(issues.map { "- " + $0 }.joined(separator: "\n"))
        Return a corrected plan for the original request.
        """
    }

    public static func failure(status: Int32, stderr: String) -> String {
        let tail = String(stderr.suffix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        The commands ran and failed with exit status \(status).
        Error output:
        \(tail.isEmpty ? "(none)" : tail)
        Return a corrected plan for the original request. Don't repeat the approach that failed.
        """
    }

    /// Small models sometimes wrap a command in backticks or prefix it with a prompt sign.
    public static func clean(_ command: String) -> String {
        var c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("```") {
            c = c.split(separator: "\n").filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        while c.hasPrefix("`") && c.hasSuffix("`") && c.count > 1 { c = String(c.dropFirst().dropLast()) }
        if c.hasPrefix("$ ") { c.removeFirst(2) }
        return c.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
